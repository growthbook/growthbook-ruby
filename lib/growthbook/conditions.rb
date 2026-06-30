# frozen_string_literal: true

require 'json'

module Growthbook
  # internal use only
  # Utils for condition evaluation
  class Conditions
    # Evaluate a targeting conditions hash against an attributes hash
    # Both attributes and conditions only have string keys (no symbols)
    def self.eval_condition(attributes, condition, saved_groups = {})
      condition.each do |key, value|
        case key
        when '$or'
          return false unless eval_or(attributes, value, saved_groups)
        when '$nor'
          return false if eval_or(attributes, value, saved_groups)
        when '$and'
          return false unless eval_and(attributes, value, saved_groups)
        when '$not'
          return false if eval_condition(attributes, value, saved_groups)
        else
          return false unless eval_condition_value(value, get_path(attributes, key), saved_groups)
        end
      end

      true
    end

    # Helper function to ensure conditions only have string keys (no symbols)
    def self.parse_condition(condition)
      case condition
      when Array
        return condition.map { |v| parse_condition(v) }
      when Hash
        return condition.to_h { |k, v| [k.to_s, parse_condition(v)] }
      end
      condition
    end

    def self.eval_or(attributes, conditions, saved_groups = {})
      return true if conditions.length <= 0

      conditions.each do |condition|
        return true if eval_condition(attributes, condition, saved_groups)
      end
      false
    end

    def self.eval_and(attributes, conditions, saved_groups = {})
      conditions.each do |condition|
        return false unless eval_condition(attributes, condition, saved_groups)
      end
      true
    end

    def self.operator_object?(obj)
      obj.each do |key, _value|
        return false if key[0] != '$'
      end
      true
    end

    def self.get_type(attribute_value)
      return 'string' if attribute_value.is_a? String
      return 'number' if attribute_value.is_a? Integer
      return 'number' if attribute_value.is_a? Float
      return 'boolean' if [true, false].include?(attribute_value)
      return 'array' if attribute_value.is_a? Array
      return 'null' if attribute_value.nil?

      'object'
    end

    def self.get_path(attributes, path)
      path = path.to_s if path.is_a?(Symbol)

      parts = path.split('.')
      current = attributes

      parts.each do |value|
        return nil unless current.is_a?(Hash) && current&.key?(value)

        current = current[value]
      end

      current
    end

    def self.eval_condition_value(condition_value, attribute_value, saved_groups = {}, insensitive: false)
      if condition_value.is_a?(Hash) && operator_object?(condition_value)
        condition_value.each do |key, value|
          return false unless eval_operator_condition(key, attribute_value, value, saved_groups)
        end
        return true
      end
      return condition_value.casecmp?(attribute_value) if insensitive && condition_value.is_a?(String) && attribute_value.is_a?(String)

      condition_value.to_json == attribute_value.to_json
    end

    def self.elem_match(condition, attribute_value, saved_groups = {})
      return false unless attribute_value.is_a? Array

      attribute_value.each do |item|
        if operator_object?(condition)
          return true if eval_condition_value(condition, item, saved_groups)
        elsif eval_condition(item, condition, saved_groups)
          return true
        end
      end
      false
    end

    def self.compare(val1, val2)
      if val1.is_a?(Numeric) || val2.is_a?(Numeric)
        val1 = val1.is_a?(Numeric) ? val1 : val1.to_f
        val2 = val2.is_a?(Numeric) ? val2 : val2.to_f
      end

      return 1 if val1 > val2
      return -1 if val1 < val2

      0
    end

    def self.eval_version_operator(operator, attribute_value, condition_value)
      a = padded_version_string(attribute_value)
      b = padded_version_string(condition_value)
      case operator
      when '$veq' then a == b
      when '$vne' then a != b
      when '$vgt' then a > b
      when '$vgte' then a >= b
      when '$vlt' then a < b
      when '$vlte' then a <= b
      else false
      end
    end

    def self.eval_compare_operator(operator, attribute_value, condition_value)
      result = compare(attribute_value, condition_value)
      case operator
      when '$eq' then result.zero?
      when '$ne' then result != 0
      when '$lt' then result.negative?
      when '$lte' then result <= 0
      when '$gt' then result.positive?
      when '$gte' then result >= 0
      else false
      end
    rescue StandardError
      # Values weren't comparable (e.g. booleans); fall back to direct equality
      return attribute_value == condition_value if operator == '$eq'
      return attribute_value != condition_value if operator == '$ne'

      false
    end

    def self.eval_operator_condition(operator, attribute_value, condition_value, saved_groups = {})
      case operator
      when '$veq', '$vne', '$vgt', '$vgte', '$vlt', '$vlte'
        eval_version_operator(operator, attribute_value, condition_value)
      when '$eq', '$ne', '$lt', '$lte', '$gt', '$gte'
        eval_compare_operator(operator, attribute_value, condition_value)
      when '$regex'
        silence_warnings do
          re = Regexp.new(condition_value)
          !!attribute_value.match(re)
        rescue StandardError
          false
        end
      when '$regexi'
        silence_warnings do
          re = Regexp.new(condition_value, Regexp::IGNORECASE)
          !!attribute_value.match(re)
        rescue StandardError
          false
        end
      when '$in'
        return false unless condition_value.is_a?(Array)

        in?(attribute_value, condition_value)
      when '$nin'
        return false unless condition_value.is_a?(Array)

        !in?(attribute_value, condition_value)
      when '$ini'
        return false unless condition_value.is_a?(Array)

        in?(attribute_value, condition_value, insensitive: true)
      when '$nini'
        return false unless condition_value.is_a?(Array)

        !in?(attribute_value, condition_value, insensitive: true)
      when '$inGroup'
        return false unless condition_value.is_a?(String)
        return false unless saved_groups.key?(condition_value)

        in?(attribute_value, saved_groups[condition_value] || [])
      when '$notInGroup'
        return false unless condition_value.is_a?(String)
        return true unless saved_groups.key?(condition_value)

        !in?(attribute_value, saved_groups[condition_value] || [])
      when '$elemMatch'
        elem_match(condition_value, attribute_value, saved_groups)
      when '$size'
        return false unless attribute_value.is_a? Array

        eval_condition_value(condition_value, attribute_value.length, saved_groups)
      when '$all'
        in_all?(condition_value, attribute_value, saved_groups, false)
      when '$alli'
        return false unless condition_value.is_a?(Array)

        in_all?(condition_value, attribute_value, saved_groups, true)
      when '$exists'
        exists = !attribute_value.nil?
        if condition_value
          exists
        else
          !exists
        end
      when '$type'
        condition_value == get_type(attribute_value)
      when '$not'
        !eval_condition_value(condition_value, attribute_value, saved_groups)
      else
        false
      end
    end

    def self.in_all?(condition_values, attribute_value, saved_groups, insensitive)
      return false unless attribute_value.is_a? Array

      condition_values.each do |cond|
        passed = attribute_value.any? { |attr| eval_condition_value(cond, attr, saved_groups, insensitive: insensitive) }
        return false unless passed
      end
      true
    end

    def self.padded_version_string(input)
      # Remove build info and leading `v` if any
      # Split version into parts (both core version numbers and pre-release tags)
      # "v1.2.3-rc.1+build123" -> ["1","2","3","rc","1"]
      parts = input.gsub(/(^v|\+.*$)/, '').split(/[-.]/)

      # If it's SemVer without a pre-release, add `~` to the end
      # ["1","0","0"] -> ["1","0","0","~"]
      # "~" is the largest ASCII character, so this will make "1.0.0" greater than "1.0.0-beta" for example
      parts << '~' if parts.length == 3

      # Left pad each numeric part with spaces so string comparisons will work ("9">"10", but " 9"<"10")
      parts.map do |part|
        /^[0-9]+$/.match?(part) ? part.rjust(5, ' ') : part
      end.join('-')
    end

    def self.in?(actual, expected, insensitive: false)
      expected ||= []

      if insensitive
        fold = ->(val) { val.is_a?(String) ? val.downcase : val }
        folded_expected = expected.map { |exp| fold.call(exp) }
        return actual.any? { |el| folded_expected.include?(fold.call(el)) } if actual.is_a?(Array)

        return folded_expected.include?(fold.call(actual))
      end

      return expected.include?(actual) unless actual.is_a?(Array)

      (actual & expected).any?
    end

    # Sets $VERBOSE for the duration of the block and back to its original
    # value afterwards. Used for testing invalid regexes.
    def self.silence_warnings
      old_verbose = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = old_verbose
    end
  end
end
