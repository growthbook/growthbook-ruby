# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Growthbook
  # Plugins for Growthbook::Context, passed with the `plugins:` option
  module Plugins
    # Sends Feature Evaluated, Experiment Viewed and custom (Context#log_event) events to the
    # GrowthBook ingestor, a port of the TS SDK's growthbookTrackingPlugin.
    #
    # Create one instance per process and pass it to every Context, e.g. in an initializer:
    #
    #   TRACKING = Growthbook::Plugins::Tracking.new
    #   gb = Growthbook::Context.new(client_key: 'sdk-abc123', features: features, plugins: [TRACKING])
    #
    # The instance owns a queue and a background thread that sends the queued events in batches
    # over one kept-alive connection, so a Context per request doesn't start a thread or a
    # connection per request. It is thread-safe, survives a fork (the child starts its own queue
    # and thread) and flushes the queue at exit. The thread stops after WORKER_IDLE_TIMEOUT
    # seconds without events and starts again with the next one.
    #
    # Every attribute of the user is sent to the ingestor (see #initialize for the identity
    # fields). Use event_filter, or leave attributes out of the Context, to keep data you must
    # not share from being sent.
    class Tracking
      DEFAULT_INGESTOR_HOST = 'https://us-east-1.gb-ingest.com'

      # Attributes sent as top-level fields of an event rather than inside context_json
      IDENTITY_ATTRIBUTES = %w[user_id device_id anonymous_id id page_id session_id].freeze

      # Optional top-level fields, only sent when the attribute is a non-empty String
      OPTIONAL_FIELDS = {
        'utm_campaign' => 'utmCampaign',
        'utm_content'  => 'utmContent',
        'utm_medium'   => 'utmMedium',
        'utm_source'   => 'utmSource',
        'utm_term'     => 'utmTerm',
        'page_title'   => 'pageTitle'
      }.freeze

      TOP_LEVEL_ATTRIBUTES = (IDENTITY_ATTRIBUTES + OPTIONAL_FIELDS.values).freeze

      DEDUPED_EVENTS = [Growthbook::EVENT_FEATURE_EVALUATED, Growthbook::EVENT_EXPERIMENT_VIEWED].freeze

      # Seconds without events after which the background thread stops
      WORKER_IDLE_TIMEOUT = 30

      # Creating this many instances means one is made per context instead of once per process
      INSTANCE_WARNING_THRESHOLD = 100

      # Instances are held weakly, so one that is no longer used can be garbage-collected; a
      # single at_exit hook flushes the rest
      @instances = ObjectSpace::WeakMap.new
      @instance_count = 0
      @registry_mutex = Mutex.new

      class << self
        # @private Called by #initialize
        def register(instance)
          @registry_mutex.synchronize do
            @instances[instance] = true
            @instance_count += 1
            warn("#{INSTANCE_WARNING_THRESHOLD} GrowthBook tracking plugins created: create one per process and pass it to every Context") if @instance_count == INSTANCE_WARNING_THRESHOLD
          end
        end

        # Shut down every instance that is still alive. Runs at exit.
        def shutdown_all
          instances = @registry_mutex.synchronize { @instances.keys }
          instances.each(&:shutdown)
        end
      end

      # Registered when the gem is loaded, so it runs after the at_exit hooks the app registers
      # later, and events they track are still sent
      at_exit { shutdown_all }

      # @param ingestor_host [String] Where events are sent, as "#{ingestor_host}/track"
      # @param queue_flush_interval [Numeric] Seconds to collect events before sending them as one batch
      # @param enable [true, false] When false, events are still filtered, deduped and logged
      #   with debug, but not sent
      # @param enable_feature_usage_events [true, false] When false, Feature Evaluated is not sent
      # @param debug [true, false] Write each event to stderr with warn. The output contains the
      #   user's attributes, so don't enable it in production
      # @param dedupe_cache_size [Integer] How many recent Feature Evaluated and Experiment Viewed
      #   events are remembered to skip duplicates (least recently seen forgotten first)
      # @param dedupe_key_attributes [Array<String>] Attributes that identify a user for
      #   deduplication. By default Feature Evaluated uses all attributes, since one instance serves
      #   many users, and Experiment Viewed relies on its hashValue
      # @param event_filter [#call, nil] Called with `{ event_name:, properties:, attributes:, url: }`;
      #   the event is dropped unless it returns a truthy value
      # @param max_queue_size [Integer] Events queued beyond this are dropped, e.g. while the
      #   ingestor is slow, so memory stays bounded
      # @param http_timeout [Numeric] Open and read timeout of a request, in seconds
      def initialize(
        ingestor_host: DEFAULT_INGESTOR_HOST,
        queue_flush_interval: 0.1,
        enable: true,
        enable_feature_usage_events: true,
        debug: false,
        dedupe_cache_size: 1000,
        dedupe_key_attributes: [],
        event_filter: nil,
        max_queue_size: 10_000,
        http_timeout: 5
      )
        @ingestor_host = (ingestor_host || DEFAULT_INGESTOR_HOST).to_s.chomp('/')
        raise ArgumentError, "ingestor_host must be an http(s) URL, got #{@ingestor_host.inspect}" unless @ingestor_host.match?(%r{\Ahttps?://[^/]})

        @ingestor_uri = URI(@ingestor_host)

        @queue_flush_interval = queue_flush_interval
        @enable = enable
        @enable_feature_usage_events = enable_feature_usage_events
        @debug = debug
        @dedupe_cache_size = dedupe_cache_size
        @dedupe_key_attributes = (dedupe_key_attributes || []).map(&:to_s)
        @event_filter = event_filter
        @max_queue_size = max_queue_size
        @http_timeout = http_timeout

        @dedupe_cache = {}
        @stopped = false
        reset_queue
        Tracking.register(self)
      end

      # Plugin entry point: send the events of this context to the ingestor
      #
      # @param context [Growthbook::Context]
      def call(context)
        client_key = context.client_key.to_s
        raise ArgumentError, 'client_key must be specified to use event logging' if client_key.empty?

        # Unlike TS, nothing is sent on Context#destroy: with a context per request that would
        # send a request per request. The queue is shared, so the batch goes out on schedule.
        context.event_logger = lambda do |event_name, properties, user_context|
          track(client_key, event_name, properties, user_context)
        end
        nil
      end

      # Filter, dedupe and queue one event. Called by the event logger of each context.
      def track(client_key, event_name, properties, user_context)
        # @type var data: event_data
        data = {
          event_name: event_name,
          properties: properties || {},
          attributes: user_context[:attributes] || {},
          url: user_context[:url] || ''
        }
        return if !@enable_feature_usage_events && event_name == Growthbook::EVENT_FEATURE_EVALUATED
        return if @event_filter && !@event_filter.call(data)

        reset_after_fork
        return if duplicate?(client_key, data)

        body = serialize(event_payload(data))
        return if body.nil?

        warn("Logging event to GrowthBook: #{body}") if @debug
        enqueue(client_key, body) if @enable
        nil
      end

      # Send every queued event now, in the calling thread
      def flush
        reset_after_fork
        batch = @mutex.synchronize do
          events = @queue
          @queue = []
          @dropping = false
          events
        end
        batch.group_by(&:first).each do |client_key, events|
          send_events(client_key, events.map(&:last))
        end
        nil
      end

      # Stop the background thread after it sends what is queued, waiting at most `timeout`
      # seconds. Events tracked afterwards are dropped. Called at exit.
      def shutdown(timeout: 5)
        # A forked child that never tracked anything holds a copy of the parent's queue: the
        # parent sends those events, so the child must not
        return if Process.pid != @pid

        worker = @mutex.synchronize do
          @stopped = true
          @wakeup.broadcast
          @worker
        end
        worker&.join(timeout)
        flush
        @send_mutex.synchronize { close_connection }
        nil
      end

      private

      def reset_queue
        @pid = Process.pid
        @mutex = Mutex.new
        @wakeup = ConditionVariable.new
        @queue = []
        @worker = nil
        @dropping = false
        @send_mutex = Mutex.new
        # Dropped, not closed: after a fork the socket still belongs to the parent
        @http = nil
      end

      # A forked child gets a copy of the queue and of a mutex that a parent thread may hold, but
      # not the parent's thread. Start over: the parent sends what it queued.
      def reset_after_fork
        reset_queue if Process.pid != @pid
      end

      def duplicate?(client_key, data)
        event_name = data[:event_name]
        return false unless DEDUPED_EVENTS.include?(event_name)

        key = dedupe_key(client_key, data)
        @mutex.synchronize do
          seen = !@dedupe_cache.delete(key).nil?
          @dedupe_cache[key] = true
          @dedupe_cache.shift if !seen && @dedupe_cache.size > @dedupe_cache_size
          seen
        end
      end

      def dedupe_key(client_key, data)
        attributes = data[:attributes]
        identity = @dedupe_key_attributes
        identity = attributes.keys.map(&:to_s).sort if identity.empty? && data[:event_name] == Growthbook::EVENT_FEATURE_EVALUATED
        key = [client_key, data[:event_name], data[:properties], identity.map { |name| [name, attributes[name]] }]
        begin
          key.to_json
        rescue StandardError
          key.inspect
        end
      end

      def event_payload(data)
        attributes = data[:attributes]
        payload = {
          'event_name'      => data[:event_name],
          'properties_json' => data[:properties],
          'user_id'         => string_or_nil(attributes['user_id']),
          'device_id'       => string_or_nil(first_present(attributes, %w[device_id anonymous_id id])),
          'page_id'         => string_or_nil(attributes['page_id']),
          'session_id'      => string_or_nil(attributes['session_id'])
        }
        OPTIONAL_FIELDS.each do |field, attribute|
          value = string_or_nil(attributes[attribute])
          payload[field] = value unless value.nil? || value.empty?
        end
        payload['sdk_language'] = 'ruby'
        payload['sdk_version'] = Growthbook::VERSION
        payload['url'] = data[:url]
        payload['context_json'] = attributes.reject { |name, _| TOP_LEVEL_ATTRIBUTES.include?(name.to_s) }
        payload
      end

      def first_present(attributes, names)
        names.each do |name|
          value = attributes[name]
          return value unless value.nil?
        end
        nil
      end

      def string_or_nil(value)
        value.is_a?(String) ? value : nil
      end

      # Serialize when queued, so later changes to the attributes don't leak into the event and
      # one event that can't be serialized doesn't take down the whole batch
      def serialize(payload)
        JSON.generate(payload)
      rescue StandardError => e
        warn("GrowthBook tracking dropped an event that can't be serialized to JSON: #{e.class}")
        nil
      end

      def enqueue(client_key, body)
        @mutex.synchronize do
          return if @stopped

          if @queue.size >= @max_queue_size
            warn('GrowthBook tracking queue is full, dropping events') unless @dropping
            @dropping = true
            return
          end

          @queue << [client_key, body]
          start_worker
          # Only the first event wakes the worker, so the rest don't cut the batch window short
          @wakeup.signal if @queue.size == 1
        end
      end

      # Called with @mutex held
      def start_worker
        return if @worker&.alive?

        @worker = Thread.new { run_worker }
      end

      def run_worker
        loop do
          idle = @mutex.synchronize do
            @wakeup.wait(@mutex, WORKER_IDLE_TIMEOUT) if @queue.empty? && !@stopped
            if @queue.empty?
              # Nothing to send: stop, and let the next event start a new thread
              @worker = nil
              true
            else
              @wakeup.wait(@mutex, @queue_flush_interval) unless @stopped
              false
            end
          end
          break if idle

          flush
        end
      rescue StandardError => e
        @mutex.synchronize { @worker = nil }
        warn("GrowthBook tracking worker stopped: #{e.class}")
      end

      def send_events(client_key, events)
        path = "#{@ingestor_uri.path}/track?client_key=#{URI.encode_www_form_component(client_key)}"
        request = Net::HTTP::Post.new(path, 'Accept' => 'application/json', 'Content-Type' => 'text/plain')
        request.body = "[#{events.join(',')}]"

        # One connection, kept alive between batches; the worker, #flush and #shutdown take turns
        @send_mutex.synchronize do
          response = connection.request(request)
          warn("GrowthBook tracking failed: HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)
        rescue StandardError => e
          close_connection
          # Only the class: the message can contain the request body, and so user data
          warn("GrowthBook tracking failed: #{e.class}")
        end
      end

      # Called with @send_mutex held
      def connection
        http = @http
        return http if http&.started?

        http = Net::HTTP.new(@ingestor_uri.host.to_s, @ingestor_uri.port)
        http.use_ssl = @ingestor_uri.scheme == 'https'
        http.open_timeout = @http_timeout
        http.read_timeout = @http_timeout
        http.start
        @http = http
      end

      # Called with @send_mutex held
      def close_connection
        http = @http
        @http = nil
        http.finish if http&.started?
      rescue IOError, SystemCallError
        nil
      end
    end
  end
end
