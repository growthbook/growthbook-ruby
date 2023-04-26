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

    def initialize(endpoint:, decryption_key:)
      @endpoint = endpoint
      @decryption_key = decryption_key
      @features_json = {}
    end

    def fetch
      uri = URI(endpoint)
      res = Net::HTTP.get_response(uri)

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

      raise FeatureFetchError if @response.nil?
      raise FeatureParseError if @response.empty?

      features_json
    end

    private

    attr_reader :response

    def use_decryption?
      !decryption_key.nil?
    end

    def parsed_plain_text_response
      @features_json = parsed_response['features'] unless @response.nil?
    rescue StandardError
      nil
    end

    def parsed_decrypted_response
      k = decryption_key
      return nil if k.nil?

      decrypted_str = Growthbook::DecryptionUtil.decrypt(parsed_response['encryptedFeatures'], key: k)
      @features_json = JSON.parse(decrypted_str) unless decrypted_str.nil?
    rescue StandardError
      nil
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
