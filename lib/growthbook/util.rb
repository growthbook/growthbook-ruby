require "fnv"

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

    def self.chooseVariation(userId, experiment)
      testId = experiment.id
      weights = experiment.getScaledWeights()

      # Hash the user id and testName to a number from 0 to 1
      n = (FNV.new.fnv1a_32(userId + testId)%1000)/1000.0

      cumulativeWeight = 0

      match = -1
      i = 0
      weights.each do |weight|
        cumulativeWeight += weight
        if n < cumulativeWeight
          match = i
          break
        end
        i+=1
      end

      return match
    end
  end
end