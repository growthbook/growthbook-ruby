# frozen_string_literal: true

require 'base64'
require 'fnv'
require 'bigdecimal'
require 'bigdecimal/util'
require 'openssl'

module Growthbook
  # internal use only
  class Util
    def self.check_rule(actual, op, desired)
      # Check if both strings are numeric so we can do natural ordering
      # for greater than / less than operators
      numeric = begin
        (!Float(actual).nil? && !Float(desired).nil?)
      rescue StandardError
        false
      end

      case op
      when '='
        numeric ? Float(actual).to_d == Float(desired).to_d : actual == desired
      when '!='
        numeric ? Float(actual).to_d != Float(desired).to_d : actual != desired
      when '>'
        numeric ? Float(actual) > Float(desired) : actual > desired
      when '<'
        numeric ? Float(actual) < Float(desired) : actual < desired
      when '~'
        begin
          !!(actual =~ Regexp.new(desired))
        rescue StandardError
          false
        end
      when '!~'
        begin
          actual !~ Regexp.new(desired)
        rescue StandardError
          false
        end
      else
        true
      end
    end

    # @return [String, nil] Hash, or nil if the hash version is invalid
    def self.hash(seed:, value:, version:)
      return (FNV.new.fnv1a_32(value + seed) % 1000) / 1000.0 if version == 1
      return (FNV.new.fnv1a_32(FNV.new.fnv1a_32(seed + value).to_s) % 10_000) / 10_000.0 if version == 2

      nil
    end

    def self.in_namespace(hash_value, namespace)
      n = hash(seed: "__#{namespace[0]}", value: hash_value, version: 1)
      n >= namespace[1] && n < namespace[2]
    end

    def self.get_equal_weights(num_variations)
      return [] if num_variations < 1

      weights = []
      (1..num_variations).each do |_i|
        weights << (1.0 / num_variations)
      end
      weights
    end

    # Determine bucket ranges for experiment variations
    def self.get_bucket_ranges(num_variations, coverage = 1, weights = [])
      # Make sure coverage is within bounds
      coverage = 1 if coverage.nil?
      coverage = 0 if coverage.negative?
      coverage = 1 if coverage > 1

      # Default to equal weights
      weights = get_equal_weights(num_variations) if !weights || weights.length != num_variations

      # If weights don't add up to 1 (or close to it), default to equal weights
      total = weights.sum
      weights = get_equal_weights(num_variations) if total < 0.99 || total > 1.01

      # Convert weights to ranges
      cumulative = 0
      ranges = []
      weights.each do |w|
        start = cumulative
        cumulative += w
        ranges << [start, start + (coverage * w)]
      end

      ranges
    end

    # Chose a variation based on a hash and range
    def self.choose_variation(num, ranges)
      ranges.each_with_index do |range, i|
        return i if num >= range[0] && num < range[1]
      end
      -1
    end

    # Get an override variation from a url querystring
    # e.g. http://localhost?my-test=1 will return `1` for id `my-test`
    def self.get_query_string_override(id, url, num_variations)
      # Skip if url is empty
      return nil if url == ''

      # Parse out the query string
      parsed = URI(url)
      return nil unless parsed.query

      qs = URI.decode_www_form(parsed.query)

      # Look for `id` in the querystring and get the value
      vals = qs.assoc(id)
      return nil unless vals

      val = vals.last
      return nil unless val

      # Parse the value as an integer
      n = begin
        Integer(val)
      rescue StandardError
        nil
      end

      # Make sure the integer is within range
      return nil if n.nil?
      return nil if n.negative?
      return nil if n >= num_variations

      n
    end

    def self.in_range?(num, range)
      num >= range[0] && num < range[1]
    end

    def self.decrypt_payload(payload = '', key:)
      DecryptionUtil.decrypt(payload, key: key)
    end
  end
end
