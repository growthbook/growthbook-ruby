# frozen_string_literal: true

require 'json'

module Growthbook
  class Conditions

    def self.evalCondition(attributes, condition)
      return self.evalOr(attributes, condition['$or']) if condition.has_key?('$or')
      return !self.evalOr(attributes, condition['$nor']) if condition.has_key?('$nor')
      return self.evalAnd(attributes, condition['$and']) if condition.has_key?('$and')
      return !self.evalCondition(attributes, condition['$not']) if condition.has_key?('$not')

      condition.each do |key, value|
        return false unless self.evalConditionValue(value, getPath(attributes, key))
      end

      true
    end

    private

    def self.evalOr(attributes, conditions)
      return true if conditions.length <= 0

      conditions.each do |condition|
        return true if self.evalCondition(attributes, condition)
      end
      false
    end

    def self.evalAnd(attributes, conditions)
      conditions.each do |condition|
        return false unless self.evalCondition(attributes, condition)
      end
      true
    end

    def self.isOperatorObject(obj)
      obj.each do |key, _value|
        return false if key[0] != '$'
      end
      true
    end

    def self.getType(attributeValue)
      return 'string' if attributeValue.is_a? String
      return 'number' if attributeValue.is_a? Integer
      return 'number' if attributeValue.is_a? Float
      return 'boolean' if !!attributeValue == attributeValue
      return 'array' if attributeValue.is_a? Array
      return 'null' if attributeValue.nil?

      'object'
    end

    def self.getPath(attributes, path)
      parts = path.split('.')
      current = attributes

      parts.each do |value|
        if current.has_key?(value)
          current = current[value]
        else
          return nil
        end
      end

      current
    end

    def self.evalConditionValue(conditionValue, attributeValue)      
      if conditionValue.is_a?(Hash) && self.isOperatorObject(conditionValue)
        conditionValue.each do |key, value|
          return false unless self.evalOperatorCondition(key, attributeValue, value)
        end
        return true
      end
      conditionValue.to_json == attributeValue.to_json
    end

    def self.elemMatch(condition, attributeValue)
      return false unless attributeValue.is_a? Array

      attributeValue.each do |item|
        if self.isOperatorObject(condition)
          return true if self.evalConditionValue(condition, item)
        elsif self.evalCondition(item, condition)
          return true
        end
      end
      false
    end

    def self.evalOperatorCondition(operator, attributeValue, conditionValue)
      case operator
      when '$eq'
        attributeValue == conditionValue
      when '$ne'
        attributeValue != conditionValue
      when '$lt'
        attributeValue < conditionValue
      when '$lte'
        attributeValue <= conditionValue
      when '$gt'
        attributeValue > conditionValue
      when '$gte'
        attributeValue >= conditionValue
      when '$regex'
        self.silence_warnings do
          begin
            re = Regexp.new(conditionValue)
            !!attributeValue.match(re)
          rescue => e
            false
          end
        end
      when '$in'
        conditionValue.include? attributeValue
      when '$nin'
        !(conditionValue.include? attributeValue)
      when '$elemMatch'
        self.elemMatch(conditionValue, attributeValue)
      when '$size'
        return false unless attributeValue.is_a? Array

        self.evalConditionValue(conditionValue, attributeValue.length)
      when '$all'
        return false unless attributeValue.is_a? Array

        conditionValue.each do |condition|
          passed = false
          attributeValue.each do |attr|
            passed = true if self.evalConditionValue(condition, attr)
          end
          return false unless passed
        end
        true
      when '$exists'
        exists = !attributeValue.nil?
        if !conditionValue
          !exists
        else
          exists
        end
      when '$type'
        conditionValue == self.getType(attributeValue)
      when '$not'
        !self.evalConditionValue(conditionValue, attributeValue)
      else
        false
      end
    end

    # Sets $VERBOSE for the duration of the block and back to its original
    # value afterwards. Used for testing invalid regexes.
    def self.silence_warnings(&block)
      old_verbose, $VERBOSE = $VERBOSE, nil
      yield
    ensure
      $VERBOSE = old_verbose
    end
  end
end
