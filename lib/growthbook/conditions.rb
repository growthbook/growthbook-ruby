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

    def self.eval_operator_condition(operator, attribute_value, condition_value)
      case operator
      when '$eq'
        attribute_value == condition_value
      when '$ne'
        attribute_value != condition_value
      when '$lt'
        attribute_value < condition_value
      when '$lte'
        attribute_value <= condition_value
      when '$gt'
        attribute_value > condition_value
      when '$gte'
        attribute_value >= condition_value
      when '$regex'
        silence_warnings do
          re = Regexp.new(condition_value)
          !!attribute_value.match(re)
        rescue StandardError
          false
        end
      when '$in'
        in?(attribute_value, condition_value)
      when '$nin'
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

    def self.in?(actual, expected)
      return false unless expected.is_a?(Array)
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
