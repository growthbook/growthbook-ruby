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

    # Parsed features JSON
    attr_reader :features_json

    # Parsed saved groups JSON (used by the $inGroup/$notInGroup operators)
    attr_reader :saved_groups_json

    def initialize(endpoint:, decryption_key:)
      @endpoint = endpoint
      @decryption_key = decryption_key
      @features_json = {}
      @saved_groups_json = {}
      @sse_supported = false
      @sse_client = nil
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

      @response = res.is_a?(Net::HTTPSuccess) ? res.body : nil

      return nil if response.nil?

      apply_response
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
      @response = json
      apply_response
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

      on_update&.call(features_json, saved_groups_json)
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

      @saved_groups_json = parsed['savedGroups'] || {}
      @features_json = parsed['features']
    rescue StandardError
      nil
    end

    def parsed_decrypted_response
      k = decryption_key
      return nil if k.nil?

      parsed = parsed_response
      return nil if parsed.nil?

      @saved_groups_json = decrypted_saved_groups(parsed, k)

      decrypted_str = Growthbook::DecryptionUtil.decrypt(parsed['encryptedFeatures'], key: k)
      @features_json = JSON.parse(decrypted_str) unless decrypted_str.nil?
    rescue StandardError
      nil
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
