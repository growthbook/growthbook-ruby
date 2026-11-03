# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module Growthbook
  # Reads a Server-Sent Events stream and hands each event to a callback
  class SSEClient
    DEFAULT_HEADERS = {
      'Accept'          => 'application/json; q=0.5, text/event-stream',
      'Cache-Control'   => 'no-cache',
      'Accept-Encoding' => 'identity'
    }.freeze

    # Client errors that may succeed on a later attempt
    RETRYABLE_STATUSES = [408, 429].freeze

    # Connection failures worth retrying: refused/reset sockets, DNS, timeouts, TLS, closed streams
    NETWORK_ERRORS = [IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError].freeze

    # @param on_reconnect [Proc, nil] Called after a dropped stream is open again, since the
    #   server does not replay events that were sent while the client was away
    def initialize(
      url:, on_event:, on_reconnect: nil, headers: {}, open_timeout: 30, read_timeout: 60,
      reconnect_delay: 1, max_reconnect_delay: 60
    )
      @uri = URI(url)
      @host = @uri.hostname || raise(ArgumentError, "SSE url has no host: #{url}")
      @on_event = on_event
      @on_reconnect = on_reconnect
      @connected = false
      @headers = DEFAULT_HEADERS.merge(headers)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @reconnect_delay = reconnect_delay
      @max_reconnect_delay = max_reconnect_delay
      @mutex = Mutex.new
      @wakeup = ConditionVariable.new
      @running = false
      @errors = 0
      @thread = nil
      @connection = nil
    end

    # Starts reading the stream in a background thread and returns at once
    def start
      @mutex.synchronize do
        return if running?

        @running = true
        @thread = Thread.new { run }
      end
    end

    # Closes the connection and waits for the background thread to finish
    #
    # @param timeout [Integer, Float] Seconds to wait before killing the thread
    def stop(timeout: 10)
      thread, connection = @mutex.synchronize do
        @running = false
        @wakeup.signal
        [@thread, @connection]
      end
      return if thread.nil?

      close(connection)
      # Called from an event handler, the thread is our own: it ends once the handler returns
      return if thread == Thread.current

      # Without an open connection the thread is waiting (woken above) or still connecting,
      # which can't be interrupted, so it gets only a moment before being killed
      thread.join(connection.nil? ? 0.5 : timeout) || thread.kill
      @mutex.synchronize { @thread = nil if @thread == thread }
    end

    def running?
      thread = @thread
      !thread.nil? && thread.alive?
    end

    private

    # Reconnects until stopped or until the server rejects the request for good
    def run
      @errors = 0
      while @running
        break if connect == :give_up

        @errors += 1
        wait(backoff_delay)
      end
    end

    # @return [Symbol] :give_up when retrying cannot help, :retry otherwise
    def connect
      http = Net::HTTP.new(@host, @uri.port)
      http.use_ssl = @uri.scheme == 'https'
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.max_retries = 0

      http.start do |connection|
        return :retry unless track(connection)

        request = Net::HTTP::Get.new(@uri)
        @headers.each { |name, value| request[name] = value }

        connection.request(request) do |response|
          return :give_up if permanent_failure?(response)
          next unless response.is_a?(Net::HTTPSuccess)

          @errors = 0
          reconnected = @connected
          @connected = true
          notify_reconnect if reconnected
          stream(response)
        end
      end
      :retry
    rescue *NETWORK_ERRORS
      :retry
    rescue StandardError => e
      # e.g. Net::HTTPBadResponse from a misbehaving proxy: keep retrying rather than let the thread die
      warn("GrowthBook SSE: #{e.class}: #{e.message}")
      :retry
    ensure
      @mutex.synchronize { @connection = nil }
    end

    # Publishes the open connection so stop can close it, unless stop already ran
    def track(connection)
      @mutex.synchronize do
        @connection = connection if @running
        @running
      end
    end

    def stream(response)
      parser = SSEParser.new
      response.read_body do |chunk|
        parser.feed(chunk) { |event| emit(event) }
      end
      parser.finish { |event| emit(event) }
    end

    # A 4xx other than 408/429 means the key or URL is wrong; retrying won't fix it
    def permanent_failure?(response)
      status = response.code.to_i
      return false unless status.between?(400, 499) && !RETRYABLE_STATUSES.include?(status)

      warn("GrowthBook SSE: stopping, the server answered #{status}")
      true
    end

    # A failing handler must not end the stream
    def emit(event)
      @on_event.call(event)
    rescue StandardError => e
      warn("GrowthBook SSE: event handler failed: #{e.message}")
    end

    def notify_reconnect
      @on_reconnect&.call
    rescue StandardError => e
      warn("GrowthBook SSE: reconnect handler failed: #{e.message}")
    end

    # Doubles with each failure in a row, plus up to 100% random jitter, as in the JS SDK
    def backoff_delay
      delay = @reconnect_delay.to_f * (2.0**(@errors - 1)) * (1 + rand)
      delay.clamp(0, @max_reconnect_delay)
    end

    # Sleeps, but wakes up at once when stop is called
    def wait(seconds)
      @mutex.synchronize { @wakeup.wait(@mutex, seconds) if @running }
    end

    def close(connection)
      connection&.finish
    rescue *NETWORK_ERRORS
      nil # already closed
    end
  end
end
