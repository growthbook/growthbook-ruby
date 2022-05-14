require 'json'

module Growthbook
  class Conditions
    def self.evalCondition(attributes, condition)
      if condition.has_key?("$or")
        return self.evalOr(attributes, condition["$or"])
      end
      if condition.has_key?("$nor")
        return !self.evalOr(attributes, condition["$nor"])
      end
      if condition.has_key?("$and")
        return self.evalAnd(attributes, condition["$and"])
      end
      if condition.has_key?("$not")
        return !self.evalCondition(attributes, condition["$not"])
      end

      condition.each do |key, value|
        if !self.evalConditionValue(value, self.getPath(attributes, key))
          return false
        end
      end

      return true
    end

    private

    def self.evalOr(attributes, conditions)
      return true if !conditions.length
      conditions.each do |condition|
        if self.evalCondition(attributes, condition)
          return true
        end
      end
      return false
    end

    def self.evalAnd(attributes, conditions)
      conditions.each do |condition|
        if !self.evalCondition(attributes, condition)
          return false
        end
      end
      return true
    end

    def self.isOperatorObject(obj)
      obj.each do |key, value|
        return false if key[0] != "$"
      end
      return true
    end

    def self.getType(attributeValue)
      return "string" if attributeValue.is_a? String
      return "number" if attributeValue.is_a? Integer
      return "number" if attributeValue.is_a? Float
      return "boolean" if attributeValue.is_a? Boolean
      return "array" if attributeValue.is_a? Array
      return "null" if attributeValue == nil
      return "object"
    end

    def getPaths(attributes, path)
      parts = path.split(".")
      current = attributes

      parts.each do |i, value|
        if current.has_key?(value)
          current = current[value]
        else
          return nil
        end
      end

      return current
    end

    def evalConditionValue(conditionValue, attributeValue)
      if conditionValue.is_a?(Hash) && self.isOperatorObject(conditionValue)
        conditionValue.each do |key, value|
          return false if !self.evalOperatorCondition(key, attributeValue, value)
        end
        return true
      end
      return conditionValue.to_json == attributeValue.to_json
    end

    def elemMatch(condition, attributeValue)
      return false if !(attributeValue.is_a? Array)

      attributeValue.each do |item|
        if self.isOperatorObject(condition)
          return true if self.evalConditionValue(condition, item)
        else
          return true if self.evalCondition(item, condition)
        end
      end
      return false
    end

    def evalOperatorCondition(operator, attributeValue, conditionValue)
      case operator
      when "$eq"
        return attributeValue == conditionValue
      when "$ne"
        return attributeValue != conditionValue
      when "$lt"
        return attributeValue < conditionValue
      when "$lte"
        return attributeValue <= conditionValue
      when "$gt"
        return attributeValue > conditionValue
      when "$gte"
        return attributeValue >= conditionValue
      when "$regex"
        re = Regexp.new(conditionValue)
        return !!attributeValue.match(re)
      when "$in"
        return conditionValue.include? attributeValue
      when "$nin"
        return !(conditionValue.include? attributeValue)
      when "$elemMatch"
        return self.elemMatch(conditionValue, attributeValue)
      when "$size"
        return false if !(attributeValue.is_a? Array)
        return self.evalConditionValue(conditionValue, attributeValue.length)
      when "$all"
        return false if !(attributeValue.is_a? Array)
        conditionValue.each do |condition|
          passed = false
          attributeValue.each do |attr|
            if evalConditionValue(condition, attr)
              passed = true
            end
          end
          return false if !passed
        end
        return true
      when "$exists"
        exists = (attributeValue != nil)
        if !conditionValue
          return !exists
        else
          return exists
        end
      when "$type"
        return conditionValue == self.getType(attributeValue)
      when "$not"
        return !self.evalConditionValue(conditionValue, attributeValue)
      else
        return false
      end
    end
  end
end