require "fnv"
require "uri"

module Growthbook
  class Util
    def self.checkRule(actual, op, desired)
      # Check if both strings are numeric so we can do natural ordering
      # for greater than / less than operators
      numeric = (Float(actual) != nil && Float(desired) != nil) rescue false

      case op
      when "="
        numeric ? Float(actual) == Float(desired) : actual == desired
      when "!="
        numeric ? Float(actual) != Float(desired) : actual != desired
      when ">"
        numeric ? Float(actual) > Float(desired) : actual > desired
      when "<"
        numeric ? Float(actual) < Float(desired) : actual < desired
      when "~"
        !!(actual =~ Regexp.new(desired)) rescue false
      when "!~"
        !(actual =~ Regexp.new(desired)) rescue false
      else
        true
      end
    end

    # Hash a string to a float between 0 and 1
    def self.hash(str)
      return (FNV.new.fnv1a_32(str)%1000)/1000.0
    end

    # Determine if hash is within a namespace
    def self.inNamespace(hashValue, namespace)
      n = self.hash(hashValue + "__" + namespace[0])
      return n >= namespace[1] && n < namespace[2]
    end

    # Create an array of size n with equal values that sum to 1
    def self.getEqualWeights(n)
      weights = []
      for i in 1..n
        weights << (1.0 / n)
      end
      return weights
    end

    # Determine bucket ranges for experiment variations
    def self.getBucketRanges(numVariations, coverage = 1, weights = [])
      # Make sure coverage is within bounds
      coverage = 0 if coverage < 0
      coverage = 1 if coverage > 1

      # Default to equal weights
      if weights.length != numVariations
        weights = self.getEqualWeights(numVariations)
      end

      # If weights don't add up to 1 (or close to it), default to equal weights
      total = weights.sum
      if total < 0.99 || total > 1.01
        weights = self.getEqualWeights(numVariations)
      end

      # Convert weights to ranges
      cumulative = 0
      ranges = []
      weights.each do |w|
        start = cumulative
        cumulative = cumulative + w
        ranges << [start, start + coverage * w]
      end

      return ranges
    end

    # Chose a variation based on a hash and range
    def self.chooseVariation(n, ranges)
      for i in 0..ranges.length
        if n >= ranges[i][0] && n < ranges[i][1]
          return i
        end
      end
      return -1
    end

    # Get an override variation from a url querystring
    # e.g. http://localhost?my-test=1 will return `1` for id `my-test`
    def self.getQueryStringOverride(id, url, numVariations)
      # Skip if url is empty
      return nil if url == ""

      # Parse out the query string
      parsed = URI(url)
      qs = URI.decode_www_form(parsed.query)

      # Look for `id` in the querystring and get the value
      val = qs.assoc(id).last
      return nil if !val

      # Parse the value as an integer
      n = Integer(val) rescue nil

      # Make sure the integer is within range
      return nil if n = nil
      return nil if n < 0
      return nil if n >= numVariations

      return n
    end
  end
end