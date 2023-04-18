# frozen_string_literal: true

module Growthbook
  # Overrides the default value of a Feature based on a set of requirements.
  class FeatureRule
    # @return [Hash , nil]
    attr_reader :condition
    # @return [Float , nil]
    attr_reader :coverage
    # @return [T , nil]
    attr_reader :force
    # @return [T[] , nil]
    attr_reader :variations
    # @return [String , nil]
    attr_reader :key
    # @return [Float[] , nil]
    attr_reader :weights
    # @return [Array , nil]
    attr_reader :namespace
    # @return [String , nil]
    attr_reader :hash_attribute

    def initialize(rule)
      @coverage = getOption(rule, :coverage)
      @force = getOption(rule, :force)
      @variations = getOption(rule, :variations)
      @key = getOption(rule, :key)
      @weights = getOption(rule, :weights)
      @namespace = getOption(rule, :namespace)
      @hash_attribute = getOption(rule, :hash_attribute) || getOption(rule, :hashAttribute)

      cond = getOption(rule, :condition)
      @condition = Growthbook::Conditions.parse_condition(cond) unless cond.nil?
    end

    def to_experiment(feature_key)
      return nil unless @variations

      Growthbook::InlineExperiment.new(
        key: @key || feature_key,
        variations: @variations,
        coverage: @coverage,
        weights: @weights,
        hash_attribute: @hash_attribute,
        namespace: @namespace
      )
    end

    def is_experiment?
      !!@variations
    end

    def is_force?
      !is_experiment? && !@force.nil?
    end

    def to_json(*_args)
      res = {}
      res['condition'] = @condition unless @condition.nil?
      res['coverage'] = @coverage unless @coverage.nil?
      res['force'] = @force unless @force.nil?
      res['variations'] = @variations unless @variations.nil?
      res['key'] = @key unless @key.nil?
      res['weights'] = @weights unless @weights.nil?
      res['namespace'] = @namespace unless @namespace.nil?
      res['hashAttribute'] = @hash_attribute unless @hash_attribute.nil?
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
