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
      @condition = getOption(rule, :condition)
      @coverage = getOption(rule, :coverage)
      @force = getOption(rule, :force)
      @variations = getOption(rule, :variations)
      @key = getOption(rule, :key)
      @weights = getOption(rule, :weights)
      @namespace = getOption(rule, :namespace)
      @hashAttribute = getOption(rule, :hashAttribute)
    end

    def toExperiment(feature_key)
      if !@variations
          return nil
      end

      options = {
        :coverage => @coverage,
        :weights => @weights,
        :hashAttribute => @hashAttribute,
        :namespace => @namespace
      }

      return Growthbook::InlineExperiment.new(@key || feature_key, @variations, options)
    end

    def is_experiment?
      return !!@variations
    end

    def is_force?
      return !is_experiment? && @force != nil
    end

    def to_json
      res = {}
      res["condition"] = @condition if @condition != nil
      res["coverage"] = @coverage if @coverage != nil
      res["force"] = @force if @force != nil
      res["variations"] = @variations if @variations != nil
      res["key"] = @key if @key != nil
      res["weights"] = @weights if @weights != nil
      res["namespace"] = @namespace if @namespace != nil
      res["hashAttribute"] = @hashAttribute if @hashAttribute != nil
      return res
    end

    private 
    def getOption(hash, key)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)
      return nil
    end
  end
end