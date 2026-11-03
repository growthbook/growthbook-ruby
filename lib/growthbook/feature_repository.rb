# frozen_string_literal: true

require 'net/http'
require 'uri'

module Growthbook
  # Optional class for fetching features from the GrowthBook API
  class FeatureRepository
    # [String] The SDK endpoint
    attr_reader :endpoint

    # [String, nil] Optional key for decrypting an encrypted payload
    attr_reader :decryption_key

    def initialize(endpoint:, decryption_key:)
      @endpoint = endpoint
      @decryption_key = decryption_key
      @snapshot = [{}, {}]
      @lock = Mutex.new
      @sse_supported = false
      @sse_client = nil
      @sse_pid = nil
      @sse_restart = nil
      @at_exit_registered = false
    end

    # Parsed features JSON
    def features_json
      snapshot[0]
    end

    # Parsed saved groups JSON (used by the $inGroup/$notInGroup operators)
    def saved_groups_json
      snapshot[1]
    end

    # [features_json, saved_groups_json] from the same update. Prefer this over calling
    # the two readers separately while auto refresh is running.
    def snapshot
      restart_after_fork
      @snapshot
    end

    # Whether the last fetch said the server can stream updates (`x-sse-support: enabled`)
    def sse_supported?
      @sse_supported
    end

    # Keeps features up to date by listening to the server's Server-Sent Events stream.
    # Call fetch first: streaming starts only if that response said the server supports it.
    #
    # @param streaming_host [String, nil] Base URL of the stream when it differs from the API host
    # @param headers [Hash] Extra request headers for the stream
    # @param on_update [Proc, nil] Called with (features_json, saved_groups_json) after each update
    # @return [true, false] Whether streaming was started
    def start_auto_refresh(streaming_host: nil, headers: {}, on_update: nil)
      unless sse_supported?
        warn('GrowthBook SSE: not starting, the last fetch did not report x-sse-support: enabled')
        return false
      end

      start_streaming(streaming_host, headers, on_update)
      true
    end

    def stop_auto_refresh
      client = @sse_client
      @sse_client = nil
      @sse_restart = nil
      # A client copied by fork shares the parent's socket, so it is dropped rather than closed
      client.stop if !client.nil? && @sse_pid == Process.pid
    end

    def auto_refreshing?
      restart_after_fork
      client = @sse_client
      !client.nil? && client.running?
    end

    def fetch
      uri = URI(endpoint)
      res = Net::HTTP.get_response(uri)

      # Only a successful response speaks for the server; a 5xx from a proxy usually lacks the header
      @sse_supported = res['x-sse-support'] == 'enabled' if res.is_a?(Net::HTTPSuccess)
      body = res.is_a?(Net::HTTPSuccess) ? res.body : nil

      @lock.synchronize do
        @response = body
        return nil if response.nil?

        apply_response
      end
    rescue StandardError
      nil
    end

    def fetch!
      fetch

      raise FeatureFetchError if response.nil?
      raise FeatureParseError if features_json.nil? || features_json.empty?

      features_json
    end

    private

    attr_reader :response

    # Applies a payload pushed by the SSE stream, exactly as if fetch had returned it
    def apply_payload(json)
      @lock.synchronize do
        @response = json
        apply_response
      end
    rescue StandardError
      nil
    end

    # Doesn't re-check sse_supported?, so a forked child restarts the stream its parent ran
    def start_streaming(streaming_host, headers, on_update)
      url = streaming_url(streaming_host)
      @sse_restart = -> { start_streaming(streaming_host, headers, on_update) }
      @sse_pid = Process.pid
      register_at_exit

      @sse_client ||= Growthbook::SSEClient.new(
        url: url,
        headers: headers,
        on_event: ->(event) { handle_sse_event(event, on_update) },
        # Events sent while the stream was down are not replayed, so fetch what was missed
        on_reconnect: -> { handle_sse_event({ type: 'features-updated', data: '' }, on_update) }
      )
      @sse_client.start
    end

    # After a fork (Puma, Unicorn) the stream thread lives on only in the parent, so a
    # child process starts its own stream the first time it reads features
    def restart_after_fork
      return if @sse_pid.nil? || @sse_pid == Process.pid

      @sse_pid = Process.pid
      @sse_client = nil
      @sse_restart&.call
    end

    # Closes the stream when the process exits instead of letting the socket drop
    def register_at_exit
      return if @at_exit_registered

      @at_exit_registered = true
      at_exit { stop_auto_refresh }
    end

    # Turns .../api/features/<key> into .../sub/<key>, keeping any path prefix of a proxy
    def streaming_url(streaming_host)
      uri = URI(endpoint)
      match = %r{\A(.*)/api/features/([^/]+)/?\z}.match(uri.path)
      raise ArgumentError, "Can't derive a stream URL from #{endpoint}, expected .../api/features/<key>" if match.nil?

      prefix = match[1].to_s
      client_key = match[2].to_s
      return "#{streaming_host.chomp('/')}/sub/#{client_key}" unless streaming_host.nil?

      uri.path = "#{prefix}/sub/#{client_key}"
      uri.query = nil
      uri.to_s
    end

    # "features" carries the new payload; "features-updated" only says to fetch it
    def handle_sse_event(event, on_update)
      case event[:type]
      when 'features' then apply_payload(event[:data])
      when 'features-updated' then fetch
      else return
      end

      features, saved_groups = snapshot
      on_update&.call(features, saved_groups)
    end

    def apply_response
      if use_decryption?
        parsed_decrypted_response
      else
        parsed_plain_text_response
      end
    end

    def use_decryption?
      !decryption_key.nil?
    end

    def parsed_plain_text_response
      parsed = parsed_response
      return nil if parsed.nil?

      publish(parsed['features'], parsed['savedGroups'] || {})
    rescue StandardError
      nil
    end

    def parsed_decrypted_response
      k = decryption_key
      return nil if k.nil?

      parsed = parsed_response
      return nil if parsed.nil?

      saved_groups = decrypted_saved_groups(parsed, k)
      decrypted_str = Growthbook::DecryptionUtil.decrypt(parsed['encryptedFeatures'], key: k)
      return nil if decrypted_str.nil?

      publish(JSON.parse(decrypted_str), saved_groups)
    rescue StandardError
      nil
    end

    # Swaps features and saved groups in a single assignment, so a reader never sees
    # the features of one payload next to the saved groups of another
    def publish(features, saved_groups)
      @snapshot = [features, saved_groups]
      features
    end

    def decrypted_saved_groups(parsed, key)
      if parsed['encryptedSavedGroups']
        decrypted = Growthbook::DecryptionUtil.decrypt(parsed['encryptedSavedGroups'], key: key)
        return JSON.parse(decrypted) unless decrypted.nil?
      end

      parsed['savedGroups'] || {}
    end

    def parsed_response
      res = response
      return {} if res.nil?

      JSON.parse(res)
    rescue StandardError
      {}
    end

    class FeatureFetchError < StandardError; end

    class FeatureParseError < StandardError; end
  end
end
