module Growthbook
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
    attr_reader :hashAttribute

    def initialize(rule)
      @condition = rule.has_key?(:condition) ? rule[:condition] : nil
      @coverage = rule.has_key?(:coverage) ? rule[:coverage] : nil
      @force = rule.has_key?(:force) ? rule[:force] : nil
      @variations = rule.has_key?(:variations) ? rule[:variations] : nil
      @key = rule.has_key?(:key) ? rule[:key] : nil
      @weights = rule.has_key?(:weights) ? rule[:weights] : nil
      @namespace = rule.has_key?(:namespace) ? rule[:namespace] : nil
      @hashAttribute = rule.has_key?(:hashAttribute) ? rule[:hashAttribute] : nil
    end


    def toExperiment(feature_key)
      if !isset($this->variations)
          return null
      end

      options = {
        :coverage => @coverage,
        :weights => @weights,
        :hashAttribute => @hashAttribute,
        :namespace => @namespace
      }

      return GrowthBook.Experiment.new(@key || feature_key, @variations, options)
    end
  end
end