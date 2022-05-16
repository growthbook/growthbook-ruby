# frozen_string_literal: true

module Growthbook
  class InlineExperiment
    # @returns [String]
    attr_accessor :key

    # @returns [Any]
    attr_accessor :variations

    # @returns [Bool]
    attr_accessor :active

    # @returns [Integer, nil]
    attr_accessor :force

    # @returns [Array<Float>, nil]
    attr_accessor :weights

    # @returns [Float]
    attr_accessor :coverage

    # @returns [Hash, nil]
    attr_accessor :condition

    # @returns [Array]
    attr_accessor :namespace

    # @returns [String]
    attr_accessor :hashAttribute

    # Constructor for an Experiment
    #
    # @param key [String] The unique key for this experiment
    # @param variations [Any] The array of possible variations
    # @param options [Hash]
    # @option options [Float] :coverage (1.0) The percent of elegible traffic to include in the experiment
    # @option options [Array<Float>] :weights The relative weights of the variations.
    #    Length must be the same as the number of variations. Total should add to 1.0.
    #    Default is an even split between variations
    # @option options [Boolean] :anon (false) If false, the experiment uses the logged-in user id for bucketing
    #    If true, the experiment uses the anonymous id for bucketing
    # @option options [Array<String>] :targeting Array of targeting rules in the format "key op value"
    #    where op is one of: =, !=, <, >, ~, !~
    # @option options [Integer, nil] :force If an integer, force all users to get this variation
    # @option options [Hash] :data Data to attach to the variations
    def initialize(key, variations, options = {})
      @key = key
      @variations = variations
      @active = getOption(options, :active, true)
      @force = getOption(options, :force)
      @weights = getOption(options, :weights)
      @coverage = getOption(options, :coverage, 1)
      @condition = getOption(options, :condition)
      @namespace = getOption(options, :namespace)
      @hashAttribute = getOption(options, :hashAttribute, 'id')
    end

    def getOption(hash, key, default=nil)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)
      return default
    end

    def to_json
      res = {}
      res["key"] = @key
      res["variations"] = @variations
      res['active'] = @active if @active != true && @active != nil
      res['force'] = @force if @force != nil
      res['weights'] = @weights if @weights != nil
      res['coverage'] = @coverage if @coverage != 1 && @coverage != nil
      res['condition'] = @condition if @condition != nil
      res['namespace'] = @namespace if @namespace != nil
      res['hashAttribute'] = @hashAttribute if @hashAttribute != 'id' && @hashAttribute != nil
      return res
    end
  end
end
