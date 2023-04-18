# frozen_string_literal: true

module Growthbook
  # Class for creating an inline experiment for evaluating
  class InlineExperiment
    # @return [String]
    attr_accessor :key

    # @return [Any]
    attr_accessor :variations

    # @return [Bool]
    attr_accessor :active

    # @return [Integer, nil]
    attr_accessor :force

    # @return [Array<Float>, nil]
    attr_accessor :weights

    # @return [Float]
    attr_accessor :coverage

    # @return [Hash, nil]
    attr_accessor :condition

    # @return [Array]
    attr_accessor :namespace

    # @return [String]
    attr_accessor :hash_attribute

    # Constructor for an Experiment
    #
    # @param options [Hash]
    # @option options [Array<Any>] :variations The variations to pick between
    # @option options [String] :key The unique identifier for this experiment
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
    def initialize(options = {})
      @key = getOption(options, :key, '').to_s
      @variations = getOption(options, :variations, [])
      @active = getOption(options, :active, true)
      @force = getOption(options, :force)
      @weights = getOption(options, :weights)
      @coverage = getOption(options, :coverage, 1)
      @condition = getOption(options, :condition)
      @namespace = getOption(options, :namespace)
      @hash_attribute = getOption(options, :hash_attribute) || getOption(options, :hashAttribute) || 'id'
    end

    def getOption(hash, key, default = nil)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      default
    end

    def to_json(*_args)
      res = {}
      res['key'] = @key
      res['variations'] = @variations
      res['active'] = @active if @active != true && !@active.nil?
      res['force'] = @force unless @force.nil?
      res['weights'] = @weights unless @weights.nil?
      res['coverage'] = @coverage if @coverage != 1 && !@coverage.nil?
      res['condition'] = @condition unless @condition.nil?
      res['namespace'] = @namespace unless @namespace.nil?
      res['hashAttribute'] = @hash_attribute if @hash_attribute != 'id' && !@hash_attribute.nil?
      res
    end
  end
end
