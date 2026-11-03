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

    def initialize(
      url:, on_event:, headers: {}, open_timeout: 30, read_timeout: 60, reconnect_delay: 1, max_reconnect_delay: 60
    )
      @uri = URI(url)
      @host = @uri.hostname || raise(ArgumentError, "SSE url has no host: #{url}")
      @on_event = on_event
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
      thread = @mutex.synchronize do
        @running = false
        @wakeup.signal
        @thread
      end
      return if thread.nil?

      close_connection
      thread.join(timeout) || thread.kill
      @mutex.synchronize { @thread = nil }
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
        @connection = connection
        request = Net::HTTP::Get.new(@uri)
        @headers.each { |name, value| request[name] = value }

        connection.request(request) do |response|
          return :give_up if permanent_failure?(response)
          next unless response.is_a?(Net::HTTPSuccess)

          @errors = 0
          stream(response)
        end
      end
      :retry
    rescue *NETWORK_ERRORS
      :retry
    ensure
      @connection = nil
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

    # Doubles with each failure in a row, plus up to 100% random jitter, as in the JS SDK
    def backoff_delay
      delay = @reconnect_delay.to_f * (2.0**(@errors - 1)) * (1 + rand)
      delay.clamp(0, @max_reconnect_delay)
    end

    # Sleeps, but wakes up at once when stop is called
    def wait(seconds)
      @mutex.synchronize { @wakeup.wait(@mutex, seconds) if @running }
    end

    def close_connection
      @connection&.finish
    rescue IOError
      nil # already closed
    end
  end
end
