# frozen_string_literal: true

require 'net/http'
require 'uri'

module Growthbook
  # Optional class for fetching features from the GrowthBook API
  class FeatureRepository
    # Seconds to wait before giving up on a request. Ruby's own default is 60s,
    # which is far too long to block on in a request path.
    DEFAULT_TIMEOUT = 2

    # [String] The SDK endpoint
    attr_reader :endpoint

    # [String, nil] Optional key for decrypting an encrypted payload
    attr_reader :decryption_key

    # Parsed features JSON
    attr_reader :features_json

    # Parsed saved groups JSON (used by the $inGroup/$notInGroup operators)
    attr_reader :saved_groups_json

    # [Numeric] Seconds to wait for the connection to open
    attr_reader :open_timeout

    # [Numeric] Seconds to wait for the response to be read
    attr_reader :read_timeout

    def initialize(endpoint:, decryption_key:, open_timeout: DEFAULT_TIMEOUT, read_timeout: DEFAULT_TIMEOUT)
      @endpoint = endpoint
      @decryption_key = decryption_key
      @features_json = {}
      @saved_groups_json = {}
      @open_timeout = normalize_timeout(:open_timeout, open_timeout)
      @read_timeout = normalize_timeout(:read_timeout, read_timeout)
    end

    def fetch
      uri = URI(endpoint)
      # hostname, not host: an IPv6 literal comes back from host wrapped in
      # brackets, which Net::HTTP cannot connect to
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      res = http.get(uri.request_uri)

      @response = res.is_a?(Net::HTTPSuccess) ? res.body : nil

      return nil if response.nil?

      if use_decryption?
        parsed_decrypted_response
      else
        parsed_plain_text_response
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

    # nil has to be resolved before any comparison: it would mean "wait forever"
    # if it reached Net::HTTP, and [nil, 1].max raises rather than returning 1.
    # Spelled out rather than using [seconds, MIN_TIMEOUT].max because Array#max
    # is typed as nilable, which the type check rejects.
    # nil has to be resolved before any comparison: it would mean "wait forever" if it reached
    # Net::HTTP. Everything else is accepted as given, including fractions - Net::HTTP takes them,
    # and half a second is reasonable against a proxy on the same network. Zero and negatives are
    # refused rather than clamped: Net::HTTP stores them as-is and their meaning is ambiguous
    # between failing instantly and not timing out at all.
    def normalize_timeout(name, seconds)
      seconds = DEFAULT_TIMEOUT if seconds.nil?
      raise ArgumentError, "#{name} must be a positive number of seconds, got #{seconds.inspect}" unless seconds.is_a?(Numeric) && seconds.positive?

      seconds
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
