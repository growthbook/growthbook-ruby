# frozen_string_literal: true

require 'net/http'
require 'uri'

module Growthbook
  # Reads a Server-Sent Events stream and hands each event to a callback
  class SSEClient
    DEFAULT_HEADERS = {
      'Accept'          => 'application/json; q=0.5, text/event-stream',
      'Cache-Control'   => 'no-cache',
      'Accept-Encoding' => 'identity'
    }.freeze

    def initialize(url:, on_event:, headers: {}, open_timeout: 30, read_timeout: 60)
      @uri = URI(url)
      @host = @uri.hostname || raise(ArgumentError, "SSE url has no host: #{url}")
      @on_event = on_event
      @headers = DEFAULT_HEADERS.merge(headers)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @mutex = Mutex.new
      @thread = nil
      @connection = nil
    end

    # Starts reading the stream in a background thread and returns at once
    def start
      @mutex.synchronize do
        return if running?

        @thread = Thread.new { run }
      end
    end

    # Closes the connection and waits for the background thread to finish
    #
    # @param timeout [Integer, Float] Seconds to wait before killing the thread
    def stop(timeout: 10)
      thread = @mutex.synchronize { @thread }
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

    def run
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
          next unless response.is_a?(Net::HTTPSuccess)

          parser = SSEParser.new
          response.read_body do |chunk|
            parser.feed(chunk) { |event| @on_event.call(event) }
          end
          parser.finish { |event| @on_event.call(event) }
        end
      end
    rescue IOError
      nil # stop closed the connection
    ensure
      @connection = nil
    end

    def close_connection
      @connection&.finish
    rescue IOError
      nil # already closed
    end
  end
end
