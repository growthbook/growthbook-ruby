# frozen_string_literal: true

require 'digest'
require 'net/http'
require 'uri'

module Growthbook
  # Optional class for fetching features from the GrowthBook API
  class FeatureRepository
    DEFAULT_CACHE_MUTEX = Mutex.new
    private_constant :DEFAULT_CACHE_MUTEX

    class << self
      # Cache shared by every repository that was not given one explicitly.
      #
      # Repositories are usually built per request, so a per-instance cache
      # would be empty on every fetch and the TTL would never take effect.
      def default_cache
        DEFAULT_CACHE_MUTEX.synchronize { @default_cache ||= Growthbook::InMemoryFeatureCache.new }
      end

      # Mainly useful in tests, where a shared cache otherwise leaks payloads
      # between examples
      def default_cache=(cache)
        DEFAULT_CACHE_MUTEX.synchronize { @default_cache = cache }
      end
    end

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
      @cache = cache || self.class.default_cache
    end

    def fetch
      cached = @cache.get(cache_key)
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
      @cache.set(cache_key, { 'features' => @features_json, 'savedGroups' => @saved_groups_json }, @ttl) unless result.nil?
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

    # The decryption key is part of the key because the cache is shared: two
    # repositories on the same endpoint with different keys store different
    # payloads, and keying on the endpoint alone would let one serve the other's
    # entry - including handing an undecrypted, empty payload to the repository
    # that does have a key. Digested so the key itself is never part of a cache
    # key that might be inspected or logged.
    def cache_key
      return endpoint if decryption_key.nil?

      "#{endpoint}||#{Digest::SHA256.hexdigest(decryption_key)}"
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
