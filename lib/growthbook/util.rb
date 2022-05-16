# frozen_string_literal: true

require 'fnv'

module Growthbook
  class Util
    def self.checkRule(actual, op, desired)
      # Check if both strings are numeric so we can do natural ordering
      # for greater than / less than operators
      numeric = begin
        (!Float(actual).nil? && !Float(desired).nil?)
      rescue StandardError
        false
      end

      case op
      when '='
        numeric ? Float(actual) == Float(desired) : actual == desired
      when '!='
        numeric ? Float(actual) != Float(desired) : actual != desired
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

    def self.chooseVariation(userId, experiment)
      testId = experiment.id
      weights = experiment.getScaledWeights

      # Hash the user id and testName to a number from 0 to 1
      n = (FNV.new.fnv1a_32(userId + testId) % 1000) / 1000.0

      cumulativeWeight = 0

      match = -1
      i = 0
      weights.each do |weight|
        cumulativeWeight += weight
        if n < cumulativeWeight
          match = i
          break
        end
        i += 1
      end

      match
    end

    def self.hash(str)
      (FNV.new.fnv1a_32(str) % 1000) / 1000.0
    end

    def self.inNamespace(userId, namespace)
      n = hash("#{userId}__#{namespace[0]}")
      n >= namespace[1] && n < namespace[2]
    end

    def self.getEqualWeights(numVariations)
      return [] if numVariations < 1

      weights = []
      (1..numVariations).each do |_i|
        weights << (1.0 / numVariations)
      end
      weights
    end

    # Determine bucket ranges for experiment variations
    def self.getBucketRanges(numVariations, coverage = 1, weights = [])
      # Make sure coverage is within bounds
      coverage = 1 if coverage == nil
      coverage = 0 if coverage.negative?
      coverage = 1 if coverage > 1

      # Default to equal weights
      weights = getEqualWeights(numVariations) if !weights || weights.length != numVariations

      # If weights don't add up to 1 (or close to it), default to equal weights
      total = weights.sum
      weights = getEqualWeights(numVariations) if total < 0.99 || total > 1.01

      # Convert weights to ranges
      cumulative = 0
      ranges = []
      weights.each do |w|
        start = cumulative
        cumulative += w
        ranges << [start, start + coverage * w]
      end

      ranges
    end

    # Chose a variation based on a hash and range
    def self.chooseVariationNew(n, ranges)
      ranges.each_with_index do |range, i|
        return i if (n >= range[0] && n < range[1])
      end
      return -1
    end

    # Get an override variation from a url querystring
    # e.g. http://localhost?my-test=1 will return `1` for id `my-test`
    def self.getQueryStringOverride(id, url, numVariations)
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
      return nill unless val

      # Parse the value as an integer
      n = begin
        Integer(val)
      rescue StandardError
        nil
      end

      # Make sure the integer is within range
      return nil if n.nil?
      return nil if n.negative?
      return nil if n >= numVariations

      n
    end
  end
end
