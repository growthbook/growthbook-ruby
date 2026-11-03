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
    end

    # Parsed features JSON
    def features_json
      @snapshot[0]
    end

    # Parsed saved groups JSON (used by the $inGroup/$notInGroup operators)
    def saved_groups_json
      @snapshot[1]
    end

    # [features_json, saved_groups_json] from the same update. Prefer this over calling
    # the two readers separately while auto refresh is running.
    attr_reader :snapshot

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

      @sse_client ||= Growthbook::SSEClient.new(
        url: streaming_url(streaming_host),
        headers: headers,
        on_event: ->(event) { handle_sse_event(event, on_update) }
      )
      @sse_client.start
      true
    end

    def stop_auto_refresh
      @sse_client&.stop
      @sse_client = nil
    end

    def auto_refreshing?
      client = @sse_client
      !client.nil? && client.running?
    end

    def fetch
      uri = URI(endpoint)
      res = Net::HTTP.get_response(uri)

      @sse_supported = res['x-sse-support'] == 'enabled'
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

    # Turns .../api/features/<key> into .../sub/<key>, keeping any path prefix of a proxy
    def streaming_url(streaming_host)
      uri = URI(endpoint)
      client_key = uri.path.split('/').last
      return "#{streaming_host.chomp('/')}/sub/#{client_key}" unless streaming_host.nil?

      uri.path = uri.path.sub(%r{/api/features/(?=[^/]+\z)}, '/sub/')
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
