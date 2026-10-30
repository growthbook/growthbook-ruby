# frozen_string_literal: true

require 'growthbook/util'

module Growthbook
  # A resolver for Context#add_remote_saved_groups, for remote saved groups loaded
  # into Redis by GrowthBook's loader: one `SMEMBERS gb:member:<attribute>:<value>`
  # per attribute value. Takes any client with `smembers(key)`, such as the redis
  # gem's `Redis`; the SDK doesn't depend on one. Not loaded by `require 'growthbook'`:
  #
  #   require 'growthbook/redis_resolver'
  #   context.add_remote_saved_groups(Growthbook::RedisResolver.new(Redis.new))
  #
  # A derived group checks its own attribute's value in its source group's sets:
  # `grp_vip:parent_id` looks up `gb:member:<grp_vip's attribute>:<parent_id>` and
  # matches when `grp_vip` comes back.
  class RedisResolver
    # @param redis [#smembers] A Redis client
    def initialize(redis)
      @redis = redis
    end

    # @param attributes [Hash] The attributes the groups use, keyed by attributeKey
    # @param groups [Array<Hash>] The payload's remote groups
    # @return [Array<String>] The ids of the groups the user is in
    def call(attributes, groups)
      # For each group and value: the Redis key, and the id that means a match
      checks = []
      groups.each do |group|
        source = group['valuesFrom'] ? groups.find { |g| g['id'] == group['valuesFrom'] } : group
        next if source.nil?

        lookup_values(attributes[group['attributeKey']]).each do |value|
          checks << [group['id'], "gb:member:#{source['attributeKey']}:#{value}", source['id']]
        end
      end
      members = checks.map { |check| check[1] }.uniq.each_with_object({}) do |key, out|
        out[key] = @redis.smembers(key).map(&:to_s)
      end
      # Checking for the expected id, not any id in the set, also keeps keys that
      # collide when attributes or values contain ":" (`a:b` + `c` and `a` + `b:c`)
      # from mixing up groups.
      checks.select { |_id, key, match_id| members[key].include?(match_id) }.map(&:first).uniq
    end

    private

    # Each item of an array is looked up. Numbers use JS `String(value)`, the same
    # form the loader stores them in.
    def lookup_values(value)
      (value.is_a?(Array) ? value : [value]).each_with_object([]) do |v, out|
        if v.is_a?(String)
          out << v
        elsif (v.is_a?(Integer) || v.is_a?(Float)) && v.to_f.finite?
          out << Growthbook::Util.js_number_to_s(v)
        end
      end
    end
  end
end
