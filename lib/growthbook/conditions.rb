# frozen_string_literal: true

require 'json'

module Growthbook
  # internal use only
  # Utils for condition evaluation
  class Conditions # rubocop:disable Metrics/ClassLength
    # Keys a condition can have that aren't attributes, besides $not, which is
    # also an operator on a value
    CONDITION_OPERATORS = %w[$or $nor $and $savedGroup].freeze

    # Evaluate a targeting conditions hash against an attributes hash
    # Both attributes and conditions only have string keys (no symbols)
    def self.eval_condition(attributes, condition, saved_groups = {})
      eval_condition_result(attributes, condition, saved_groups || {}) == true
    end

    # Like eval_condition, but returns nil instead of false when the result
    # depends on an operator this SDK doesn't support
    def self.eval_condition_result(attributes, condition, saved_groups = {})
      # @type var result: bool?
      result = true
      condition.each do |key, value|
        r = case key
            when '$or' then eval_or(attributes, value, saved_groups)
            when '$nor' then negate(eval_or(attributes, value, saved_groups))
            when '$and' then eval_and(attributes, value, saved_groups)
            when '$not' then negate(eval_condition_result(attributes, value, saved_groups))
            else eval_condition_value(value, get_path(attributes, key), saved_groups)
        end
        # One failing entry decides it, wherever an unsupported one is
        return false if r == false

        result = nil if r.nil?
      end
      result
    end

    # $not of an undecided result stays undecided
    def self.negate(result)
      result.nil? ? nil : !result
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

      # @type var result: bool?
      result = false
      conditions.each do |condition|
        r = eval_condition_result(attributes, condition, saved_groups)
        return true if r == true

        result = nil if r.nil?
      end
      result
    end

    def self.eval_and(attributes, conditions, saved_groups = {})
      # @type var result: bool?
      result = true
      conditions.each do |condition|
        r = eval_condition_result(attributes, condition, saved_groups)
        return false if r == false

        result = nil if r.nil?
      end
      result
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
        # @type var result: bool?
        result = true
        condition_value.each do |key, value|
          r = eval_operator_condition(key, attribute_value, value, saved_groups)
          return false if r == false

          result = nil if r.nil?
        end
        return result
      end
      return condition_value.casecmp?(attribute_value) if insensitive && condition_value.is_a?(String) && attribute_value.is_a?(String)

      condition_value.to_json == attribute_value.to_json
    end

    def self.elem_match(condition, attribute_value, saved_groups = {})
      return false unless attribute_value.is_a? Array

      # Operators test each element itself. A condition, including one that only
      # uses $or, $and, $nor, or $savedGroup, tests each element's fields.
      on_value = operator_object?(condition) && condition.keys.none? { |k| CONDITION_OPERATORS.include?(k) }
      # @type var result: bool?
      result = false
      attribute_value.each do |item|
        next if item.nil?

        r = on_value ? eval_condition_value(condition, item, saved_groups) : eval_condition_result(item, condition, saved_groups)
        return true if r == true

        result = nil if r.nil?
      end
      result
    end

    # Only two numbers or two strings can be ordered; anything else is a type mismatch
    def self.orderable?(val1, val2)
      (number?(val1) && number?(val2)) || (val1.is_a?(String) && val2.is_a?(String))
    end

    def self.number?(value)
      value.is_a?(Integer) || value.is_a?(Float)
    end

    # On a type mismatch $vne matches and every other version operator fails
    def self.eval_version_operator(operator, attribute_value, condition_value)
      return operator == '$vne' unless orderable?(attribute_value, condition_value)

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
      case operator
      when '$eq' then strict_equal?(attribute_value, condition_value)
      when '$ne' then !strict_equal?(attribute_value, condition_value)
      else
        return false unless orderable?(attribute_value, condition_value)

        case operator
        when '$lt' then attribute_value < condition_value
        when '$lte' then attribute_value <= condition_value
        when '$gt' then attribute_value > condition_value
        when '$gte' then attribute_value >= condition_value
        else false
        end
      end
    end

    # Values of different types are never equal (no "5" == 5 or 0 == nil)
    def self.strict_equal?(val1, val2)
      get_type(val1) == get_type(val2) && val1 == val2
    end

    def self.eval_operator_condition(operator, attribute_value, condition_value, saved_groups = {})
      case operator
      when '$veq', '$vne', '$vgt', '$vgte', '$vlt', '$vlte'
        eval_version_operator(operator, attribute_value, condition_value)
      when '$eq', '$ne', '$lt', '$lte', '$gt', '$gte'
        eval_compare_operator(operator, attribute_value, condition_value)
      when '$regex'
        return false unless attribute_value.is_a?(String)

        silence_warnings do
          re = Regexp.new(condition_value)
          !!attribute_value.match(re)
        rescue StandardError
          false
        end
      when '$regexi'
        return false unless attribute_value.is_a?(String)

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
        return false unless condition_value.is_a?(Array)

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
        negate(eval_condition_value(condition_value, attribute_value, saved_groups))
      else
        # Keys this SDK knows, but on a condition rather than on a value, where
        # they never match. Any other operator is unsupported.
        CONDITION_OPERATORS.include?(operator) ? false : nil
      end
    end

    def self.in_all?(condition_values, attribute_value, saved_groups, insensitive)
      return false unless attribute_value.is_a? Array

      # @type var result: bool?
      result = true
      condition_values.each do |cond|
        # @type var passed: bool?
        passed = false
        attribute_value.each do |attr|
          r = eval_condition_value(cond, attr, saved_groups, insensitive: insensitive)
          if r == true
            # @type var passed: bool?
            passed = true
            break
          end
          passed = nil if r.nil?
        end
        return false if passed == false

        result = nil if passed.nil?
      end
      result
    end

    def self.padded_version_string(input)
      # Format numbers like JS does (2.0 -> "2"); treat empty input as version 0
      input = (input.is_a?(Float) && input.finite? && input == input.floor ? input.to_i : input).to_s if number?(input)
      input = '0' if input.empty?

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
