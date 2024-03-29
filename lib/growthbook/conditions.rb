# frozen_string_literal: true

require 'json'

module Growthbook
  # internal use only
  # Utils for condition evaluation
  class Conditions
    # Evaluate a targeting conditions hash against an attributes hash
    # Both attributes and conditions only have string keys (no symbols)
    def self.eval_condition(attributes, condition)
      return eval_or(attributes, condition['$or']) if condition.key?('$or')
      return !eval_or(attributes, condition['$nor']) if condition.key?('$nor')
      return eval_and(attributes, condition['$and']) if condition.key?('$and')
      return !eval_condition(attributes, condition['$not']) if condition.key?('$not')

      condition.each do |key, value|
        return false unless eval_condition_value(value, get_path(attributes, key))
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

    def self.eval_or(attributes, conditions)
      return true if conditions.length <= 0

      conditions.each do |condition|
        return true if eval_condition(attributes, condition)
      end
      false
    end

    def self.eval_and(attributes, conditions)
      conditions.each do |condition|
        return false unless eval_condition(attributes, condition)
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

    def self.eval_condition_value(condition_value, attribute_value)
      if condition_value.is_a?(Hash) && operator_object?(condition_value)
        condition_value.each do |key, value|
          return false unless eval_operator_condition(key, attribute_value, value)
        end
        return true
      end
      condition_value.to_json == attribute_value.to_json
    end

    def self.elem_match(condition, attribute_value)
      return false unless attribute_value.is_a? Array

      attribute_value.each do |item|
        if operator_object?(condition)
          return true if eval_condition_value(condition, item)
        elsif eval_condition(item, condition)
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

    def self.eval_operator_condition(operator, attribute_value, condition_value)
      case operator
      when '$veq'
        padded_version_string(attribute_value) == padded_version_string(condition_value)
      when '$vne'
        padded_version_string(attribute_value) != padded_version_string(condition_value)
      when '$vgt'
        padded_version_string(attribute_value) > padded_version_string(condition_value)
      when '$vgte'
        padded_version_string(attribute_value) >= padded_version_string(condition_value)
      when '$vlt'
        padded_version_string(attribute_value) < padded_version_string(condition_value)
      when '$vlte'
        padded_version_string(attribute_value) <= padded_version_string(condition_value)
      when '$eq'
        begin
          compare(attribute_value, condition_value).zero?
        rescue StandardError
          false
        end
      when '$ne'
        begin
          compare(attribute_value, condition_value) != 0
        rescue StandardError
          false
        end
      when '$lt'
        begin
          compare(attribute_value, condition_value).negative?
        rescue StandardError
          false
        end
      when '$lte'
        begin
          compare(attribute_value, condition_value) <= 0
        rescue StandardError
          false
        end
      when '$gt'
        begin
          compare(attribute_value, condition_value).positive?
        rescue StandardError
          false
        end
      when '$gte'
        begin
          compare(attribute_value, condition_value) >= 0
        rescue StandardError
          false
        end
      when '$regex'
        silence_warnings do
          re = Regexp.new(condition_value)
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
      when '$elemMatch'
        elem_match(condition_value, attribute_value)
      when '$size'
        return false unless attribute_value.is_a? Array

        eval_condition_value(condition_value, attribute_value.length)
      when '$all'
        return false unless attribute_value.is_a? Array

        condition_value.each do |condition|
          passed = false
          attribute_value.each do |attr|
            passed = true if eval_condition_value(condition, attr)
          end
          return false unless passed
        end
        true
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
        !eval_condition_value(condition_value, attribute_value)
      else
        false
      end
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

    def self.in?(actual, expected)
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
