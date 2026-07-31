# frozen_string_literal: true

require 'digest'
require 'json'
require 'net/http'
require 'uri'

module Growthbook
  # Optional class for fetching remotely evaluated features from a self-hosted
  # GrowthBook proxy or edge worker.
  #
  # With remote evaluation the SDK never downloads feature definitions. It POSTs
  # the current evaluation context (attributes, forced variations, forced
  # features and URL) to `{api_host}/api/eval/{client_key}` and receives back
  # features that the proxy has already evaluated, so targeting logic and
  # unexposed feature values stay off the client.
  #
  # Remote evaluation requires a self-hosted proxy/edge: it is not available on
  # GrowthBook Cloud. It is also incompatible with SDK-side decryption (the
  # proxy handles encryption) and with sticky bucketing (handled server-side) -
  # Growthbook::Context raises when a sticky bucket service is combined with it.
  class RemoteEvalRepository
    # Seconds a cached response is reused before a new request is made
    DEFAULT_CACHE_TTL = 60

    # Cached responses are kept around for longer than they are considered fresh
    # so that a failing endpoint can still be served from a stale entry
    STALE_TTL_MULTIPLIER = 10

    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 10

    # [String] The remote evaluation endpoint the payload is POSTed to
    attr_reader :endpoint

    # [Array<String>, nil] Attributes that make up the cache key, or nil for all of them
    attr_reader :cache_key_attributes

    # [Integer] Seconds a cached response is considered fresh
    attr_reader :cache_ttl

    # Parsed features JSON of the last successful evaluation
    attr_reader :features_json

    # Parsed saved groups JSON of the last successful evaluation
    attr_reader :saved_groups_json

    # @param api_host [String] Base URL of the self-hosted proxy/edge
    # @param client_key [String] The SDK client key
    # @param cache [Growthbook::RemoteEvalCache, nil] Response cache, nil to disable caching
    # @param cache_key_attributes [Array<String>, nil] Restrict the cache key to these attributes
    # @param cache_ttl [Integer] Seconds before a cached response is refetched
    def initialize(
      api_host:,
      client_key:,
      cache: InMemoryRemoteEvalCache.new,
      cache_key_attributes: nil,
      cache_ttl: DEFAULT_CACHE_TTL,
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      read_timeout: DEFAULT_READ_TIMEOUT
    )
      raise ArgumentError, 'api_host must be provided for remote evaluation' if api_host.nil? || api_host.to_s.empty?
      raise ArgumentError, 'client_key must be provided for remote evaluation' if client_key.nil? || client_key.to_s.empty?

      host = begin
        URI(api_host.to_s).host
      rescue StandardError
        nil
      end
      raise ArgumentError, 'Cannot use remote evaluation on GrowthBook Cloud; use a self-hosted proxy or edge worker' if cloud_host?(host)

      @endpoint = "#{api_host.to_s.sub(%r{/+\z}, '')}/api/eval/#{client_key}"
      @cache = cache
      @cache_key_attributes = cache_key_attributes
      @cache_ttl = cache_ttl
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @features_json = {}
      @saved_groups_json = {}
      @flight = {}
      @flight_mutex = Mutex.new
    end

    # Evaluate the given context remotely.
    #
    # Returns a hash with the 'features' and 'savedGroups' the proxy evaluated,
    # or nil when the request failed and no cached response is available. A
    # failed request falls back to a stale cached response when there is one, so
    # a temporarily unreachable proxy does not wipe out the current features.
    def fetch(attributes: {}, forced_variations: {}, forced_features: {}, url: nil)
      payload = build_payload(attributes, forced_variations, forced_features, url)
      key = cache_key(payload)

      cached = read_cache(key)
      return apply(cached) if fresh?(cached)

      single_flight(key) do
        # Another thread may have refreshed this key while we waited for the lock
        cached = read_cache(key)
        next apply(cached) if fresh?(cached)

        response = post(payload)
        # Fall back to the stale entry, if any, rather than dropping the features
        next apply(cached) if response.nil?

        write_cache(key, response)
        apply(response)
      end
    end

    # Same as #fetch, but raises instead of silently returning nil
    def fetch!(attributes: {}, forced_variations: {}, forced_features: {}, url: nil)
      result = fetch(
        attributes: attributes,
        forced_variations: forced_variations,
        forced_features: forced_features,
        url: url
      )

      raise RemoteEvalFetchError if result.nil?

      result
    end

    private

    attr_reader :cache

    def cloud_host?(host)
      !host.nil? && host.match?(/(\A|\.)growthbook\.io\z/i)
    end

    # The wire format expected by the eval endpoint. forcedFeatures is a list of
    # [key, value] pairs, the rest are objects.
    def build_payload(attributes, forced_variations, forced_features, url)
      {
        'attributes'       => stringify_keys(attributes),
        'forcedFeatures'   => stringify_keys(forced_features).map { |k, v| [k, v] },
        'forcedVariations' => stringify_keys(forced_variations),
        'url'              => url.to_s
      }
    end

    # Forced features are deliberately left out of the cache key: they are
    # applied on this side and the proxy does not filter on them.
    def cache_key(payload)
      attributes = payload['attributes']
      unless cache_key_attributes.nil?
        attributes = cache_key_attributes.each_with_object({}) do |attribute, selected|
          selected[attribute.to_s] = payload['attributes'][attribute.to_s]
        end
      end

      key_data = {
        'ca'  => attributes,
        'fv'  => payload['forcedVariations'],
        'url' => payload['url']
      }

      # Sort recursively so that the key does not depend on insertion order,
      # which matters for caches shared between processes
      Digest::SHA256.hexdigest("#{endpoint}||#{JSON.generate(sort_recursive(key_data))}")
    end

    def sort_recursive(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).each_with_object({}) do |key, sorted|
          sorted[key] = sort_recursive(value[key])
        end
      when Array
        value.map { |item| sort_recursive(item) }
      else
        value
      end
    end

    def post(payload)
      uri = URI(endpoint)

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['User-Agent'] = 'growthbook-ruby'
      request.body = JSON.generate(payload)

      res = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      ) { |http| http.request(request) }

      return nil unless res.is_a?(Net::HTTPSuccess)

      parse(res.body)
    rescue StandardError
      nil
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)

      # A response without features is malformed - do not cache or apply it
      return nil unless parsed.is_a?(Hash) && parsed['features'].is_a?(Hash)

      {
        'features'    => parsed['features'],
        'savedGroups' => parsed['savedGroups'].is_a?(Hash) ? parsed['savedGroups'] : {}
      }
    rescue StandardError
      nil
    end

    def apply(response)
      return nil if response.nil?

      @features_json = response['features'] || {}
      @saved_groups_json = response['savedGroups'] || {}

      {
        'features'    => @features_json,
        'savedGroups' => @saved_groups_json
      }
    end

    def fresh?(cached)
      return false if cached.nil?

      expires_at = cached['expiresAt']

      !expires_at.nil? && expires_at > Time.now.to_i
    end

    def read_cache(key)
      return nil if cache.nil?

      cached = cache.get(key)

      cached.is_a?(Hash) ? cached : nil
    rescue StandardError
      nil
    end

    def write_cache(key, response)
      return if cache.nil?

      # expiresAt is wall clock so that the entry stays meaningful in a cache
      # shared between processes
      entry = response.merge('expiresAt' => Time.now.to_i + cache_ttl)

      cache.set(key, entry, cache_ttl * STALE_TTL_MULTIPLIER)
    rescue StandardError
      nil
    end

    # Serializes requests for the same cache key so that concurrent evaluations
    # of one context issue a single request. Worst case for the cleanup race is
    # a duplicate request, never a wrong result.
    def single_flight(key, &block)
      mutex = @flight_mutex.synchronize { @flight[key] ||= Mutex.new }

      begin
        mutex.synchronize(&block)
      ensure
        @flight_mutex.synchronize { @flight.delete(key) unless mutex.locked? }
      end
    end

    def stringify_keys(hash)
      return {} if hash.nil?

      hash.transform_keys(&:to_s)
    end

    class RemoteEvalFetchError < StandardError; end
  end
end
