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

    def clear
      nil
    end
  end

  # Sample in-memory cache with TTL-based expiry (not shared across processes).
  #
  # Safe to use from several threads: the default cache is shared by every
  # FeatureRepository, so concurrent access is the normal case here rather than
  # the exception. Without the lock, the expiry check in #get is a
  # check-then-delete race that can drop an entry another thread just wrote.
  class InMemoryFeatureCache < FeatureCache
    def initialize
      super
      @store = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize do
        entry = @store[key]
        next nil if entry.nil?

        expires_at = entry[:expires_at]
        if !expires_at.nil? && monotonic_now >= expires_at
          @store.delete(key)
          next nil
        end

        entry[:value]
      end
    end

    # @param ttl [Integer, nil] Seconds until expiry; nil means it never expires
    def set(key, value, ttl)
      @mutex.synchronize do
        @store[key] = { value: value, expires_at: ttl ? monotonic_now + ttl : nil }
      end

      value
    end

    def clear
      @mutex.synchronize { @store.clear }

      nil
    end

    private

    # Monotonic time so that a wall-clock change cannot keep an entry alive, or
    # expire it early, beyond its TTL
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
