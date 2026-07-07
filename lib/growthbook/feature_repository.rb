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

    # [Integer, nil] Seconds a fetched payload stays cached (nil = never expires)
    attr_reader :ttl

    def initialize(endpoint:, decryption_key:, ttl: 60, cache: nil)
      @endpoint = endpoint
      @decryption_key = decryption_key
      @features_json = {}
      @saved_groups_json = {}
      @ttl = ttl
      @cache = cache || Growthbook::InMemoryFeatureCache.new
    end

    def fetch
      cached = @cache.get(endpoint)
      unless cached.nil?
        @features_json = cached['features']
        @saved_groups_json = cached['savedGroups']
        return @features_json
      end

      uri = URI(endpoint)
      res = Net::HTTP.get_response(uri)

      @response = res.is_a?(Net::HTTPSuccess) ? res.body : nil

      return nil if response.nil?

      result = use_decryption? ? parsed_decrypted_response : parsed_plain_text_response
      @cache.set(endpoint, { 'features' => @features_json, 'savedGroups' => @saved_groups_json }, @ttl) unless result.nil?
      result
    rescue StandardError
      nil
    end

    def fetch!
      fetch

      # A cache hit populates features_json without an HTTP response, so only
      # treat a missing response as a fetch error when we also have no features
      raise FeatureFetchError if response.nil? && (features_json.nil? || features_json.empty?)
      raise FeatureParseError if features_json.nil? || features_json.empty?

      features_json
    end

    private

    attr_reader :response

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
