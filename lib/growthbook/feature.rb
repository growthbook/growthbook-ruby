# frozen_string_literal: true

module Growthbook
  # The feature with a generic value type.
  class Feature
    # @return [Any , nil]
    attr_reader :default_value

    # @return [Array<Growthbook::FeatureRule>]
    attr_reader :rules

    def initialize(feature)
      @default_value = get_option(feature, :defaultValue)

      rules = get_option(feature, :rules)

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

    def get_option(hash, key)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      nil
    end
  end
end
