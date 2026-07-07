# frozen_string_literal: true

module Growthbook
  # Extendable cache for storing fetched feature payloads.
  # Override #get / #set to plug in a shared or persistent store.
  class FeatureCache
    def get(_key)
      nil
    end

    def set(_key, _value, _ttl)
      nil
    end
  end

  # Sample in-memory cache with TTL-based expiry (not shared across processes).
  class InMemoryFeatureCache < FeatureCache
    def initialize
      super
      @store = {}
    end

    def get(key)
      entry = @store[key]
      return nil if entry.nil?

      if entry[:expires_at] && Time.now >= entry[:expires_at]
        @store.delete(key)
        return nil
      end

      entry[:value]
    end

    # @param ttl [Integer, nil] Seconds until expiry; nil means it never expires
    def set(key, value, ttl)
      @store[key] = { value: value, expires_at: ttl ? Time.now + ttl : nil }
    end
  end
end
