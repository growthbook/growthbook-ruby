# frozen_string_literal: true

module Growthbook
  # Extendable class used to cache remote evaluation responses.
  #
  # Remote evaluation results are keyed by the evaluation context, so a context
  # that has already been evaluated is served without a network call. Subclass
  # this to back the cache with a store shared between processes (Redis,
  # Memcached, ...) instead of the per-process default.
  class RemoteEvalCache
    # @return [Hash, nil] The cached entry, or nil when it is missing or expired
    def get(_key)
      nil
    end

    # @param ttl [Integer] Number of seconds after which the entry may be dropped
    # @return [void]
    def set(_key, _value, _ttl)
      nil
    end
  end

  # Thread-safe in-memory cache with a TTL and a least-recently-used bound. This
  # is what Growthbook::RemoteEvalRepository uses unless another cache is given.
  class InMemoryRemoteEvalCache < RemoteEvalCache
    # Bounds the number of cached entries (one per distinct evaluation context)
    # so a long-running process with high-cardinality attributes cannot grow the
    # cache without limit. Pass 0 to disable the bound.
    DEFAULT_MAX_SIZE = 1000

    def initialize(max_size: DEFAULT_MAX_SIZE)
      super()
      @max_size = max_size
      @entries = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize do
        entry = @entries[key]
        next nil if entry.nil?

        expires_at = entry[:expires_at]
        if !expires_at.nil? && expires_at <= monotonic_now
          @entries.delete(key)
          next nil
        end

        # Re-insert so that the entry counts as the most recently used one
        @entries.delete(key)
        @entries[key] = entry

        entry[:value]
      end
    end

    def set(key, value, ttl)
      @mutex.synchronize do
        @entries.delete(key)
        @entries[key] = {
          value: value,
          expires_at: ttl.nil? || ttl <= 0 ? nil : monotonic_now + ttl
        }

        evict_oldest while @max_size.positive? && @entries.size > @max_size
      end

      value
    end

    private

    def evict_oldest
      oldest = @entries.keys.first
      return if oldest.nil?

      @entries.delete(oldest)
    end

    # Monotonic time so that a wall-clock change cannot make entries look fresh
    # (or expired) for longer than their TTL
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
