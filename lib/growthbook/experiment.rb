# frozen_string_literal: true

module Growthbook
  class Experiment
    # @returns [String]
    attr_accessor :id

    # @returns [Integer]
    attr_accessor :variations

    # @returns [Float]
    attr_accessor :coverage

    # @returns [Array<Float>]
    attr_accessor :weights

    # @returns [Boolean]
    attr_accessor :anon

    # @returns [Array<String>]
    attr_accessor :targeting

    # @returns [Integer, nil]
    attr_accessor :force

    # @returns [Hash]
    attr_accessor :data

    # Constructor for an Experiment
    #
    # @param id [String] The unique id for this experiment
    # @param variations [Integer] The number of variations in this experiment (including the Control)
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
    def initialize(id, variations, options = {})
      @id = id
      @variations = variations
      @coverage = options[:coverage] || 1
      @weights = options[:weights] || Growthbook::Util.get_equal_weights(variations)
      @force = options.key?(:force) ? options[:force] : nil
      @anon = options.key?(:anon) ? options[:anon] : false
      @targeting = options[:targeting] || []
      @data = options[:data] || {}
    end

    def getScaledWeights
      @weights.map do |n|
        n * @coverage
      end
    end
  end
end
