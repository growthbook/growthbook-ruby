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
      @active = options.key?(:active) ? options[:active] : nil
      @force = options.key?(:force) ? options[:force] : nil
      @weights = options[:weights] || nil
      @coverage = options[:coverage] || 1
      @condition = options[:condition] || nil
      @namespace = options[:namespace] || nil
      @hashAttribute = options[:hashAttribute] || 'id'
    end
  end
end
