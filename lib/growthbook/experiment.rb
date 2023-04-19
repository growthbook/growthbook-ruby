# frozen_string_literal: true

module Growthbook
  # @deprecated
  # Internal use only
  class Experiment
    # @return [String]
    attr_accessor :id

    # @return [Integer]
    attr_accessor :variations

    # @return [Float]
    attr_accessor :coverage

    # @return [Array<Float>]
    attr_accessor :weights

    # @return [Boolean]
    attr_accessor :anon

    # @return [Array<String>]
    attr_accessor :targeting

    # @return [Integer, nil]
    attr_accessor :force

    # @return [Hash]
    attr_accessor :data

    # @deprecated Constructor for an Experiment
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
    # @deprecated
    def initialize(id, variations, options = {})
      @id = id
      @variations = variations
      @coverage = options[:coverage] || 1
      @weights = options[:weights] || getEqualWeights
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

    private

    def getEqualWeights
      weights = []
      n = @variations
      (1..n).each do |_i|
        weights << (1.0 / n)
      end
      weights
    end
  end
end
