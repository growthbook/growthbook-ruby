# frozen_string_literal: true

module Growthbook
  class InlineExperiment
    # @returns [String] The globally unique identifier for the experiment
    attr_accessor :key

    # @returns [Array<String, Integer, Hash>] The different variations to choose between
    attr_accessor :variations

    # @returns [Array<Float>] How to weight traffic between variations. Must add to 1.
    attr_accessor :weights

    # @returns [true, false] If set to false, always return the control (first variation)
    attr_accessor :active

    # @returns [Float] What percent of users should be included in the experiment (between 0 and 1, inclusive)
    attr_accessor :coverage

    # @returns [Array<Hash>] Array of ranges, one per variation
    attr_accessor :ranges

    # @returns [Hash] Optional targeting condition
    attr_accessor :condition

    # @returns [String, nil] Adds the experiment to a namespace
    attr_accessor :namespace

    # @returns [integer, nil] All users included in the experiment will be forced into the specific variation index
    attr_accessor :force

    # @returns [String] What user attribute should be used to assign variations (defaults to id)
    attr_accessor :hash_attribute

    # @returns [Integer] The hash version to use (default to 1)
    attr_accessor :hash_version

    # @returns [Array<Hash>] Meta info about the variations
    attr_accessor :meta

    # @returns [Array<Hash>] Array of filters to apply
    attr_accessor :filters

    # @returns [String, nil] The hash seed to use
    attr_accessor :seed

    # @returns [String] Human-readable name for the experiment
    attr_accessor :name

    # @returns [String, nil] Id of the current experiment phase
    attr_accessor :phase

    def initialize(options = {})
      @key = getOption(options, :key, '').to_s
      @variations = getOption(options, :variations, [])
      @weights = getOption(options, :weights)
      @active = getOption(options, :active, true)
      @coverage = getOption(options, :coverage, 1)
      @ranges = getOption(options, :ranges)
      @condition = getOption(options, :condition)
      @namespace = getOption(options, :namespace)
      @force = getOption(options, :force)
      @hash_attribute = getOption(options, :hash_attribute) || getOption(options, :hashAttribute) || 'id'
      @hash_version = getOption(options, :hash_version) || getOption(options, :hashVersion)
      @meta = getOption(options, :meta)
      @filters = getOption(options, :filters)
      @seed = getOption(options, :seed)
      @name = getOption(options, :name)
      @phase = getOption(options, :phase)
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
      res['weights'] = @weights unless @weights.nil?
      res['active'] = @active if @active != true && !@active.nil?
      res['coverage'] = @coverage if @coverage != 1 && !@coverage.nil?
      res['ranges'] = @ranges
      res['condition'] = @condition
      res['namespace'] = @namespace
      res['force'] = @force unless @force.nil?
      res['hashAttribute'] = @hash_attribute if @hash_attribute != 'id' && !@hash_attribute.nil?
      res['hashVersion'] = @hash_version
      res['meta'] = @meta
      res['filters'] = @filters
      res['seed'] = @seed
      res['name'] = @name
      res['phase'] = @phase
      res.compact
    end
  end
end
