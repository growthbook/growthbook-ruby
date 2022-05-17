# frozen_string_literal: true

module Growthbook
  class Feature
    # @return [Any , nil]
    attr_reader :default_value

    # @return [Array<Growthbook::FeatureRule>]
    attr_reader :rules

    def initialize(feature)
      @default_value = getOption(feature, :defaultValue)

      rules = getOption(feature, :rules)

      @rules = []
      rules&.each do |rule|
        @rules << Growthbook::FeatureRule.new(rule)
      end
    end

    def to_json(*_args)
      res = {}
      res['defaultValue'] = @default_value unless @default_value.nil?
      res['rules'] = []
      @rules.each do |rule|
        res['rules'] << rule.to_json
      end
      res
    end

    private

    def getOption(hash, key)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      nil
    end
  end
end
