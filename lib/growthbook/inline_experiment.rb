# frozen_string_literal: true

module Growthbook
  # Class for creating an inline experiment for evaluating
  class InlineExperiment
    # @return [String] The globally unique identifier for the experiment
    attr_accessor :key

    # @return [Array<String, Integer, Hash>] The different variations to choose between
    attr_accessor :variations

    # @return [Array<Float>] How to weight traffic between variations. Must add to 1.
    attr_accessor :weights

    # @return [true, false] If set to false, always return the control (first variation)
    attr_accessor :active

    # @return [Float] What percent of users should be included in the experiment (between 0 and 1, inclusive)
    attr_accessor :coverage

    # @return [Array<Hash>] Array of ranges, one per variation
    attr_accessor :ranges

    # @return [Hash] Optional targeting condition
    attr_accessor :condition

    # @return [String, nil] Adds the experiment to a namespace
    attr_accessor :namespace

    # @return [integer, nil] All users included in the experiment will be forced into the specific variation index
    attr_accessor :force

    # @return [String] What user attribute should be used to assign variations (defaults to id)
    attr_accessor :hash_attribute

    # @return [Integer] The hash version to use (default to 1)
    attr_accessor :hash_version

    # @return [Array<Hash>] Meta info about the variations
    attr_accessor :meta

    # @return [Array<Hash>] Array of filters to apply
    attr_accessor :filters

    # @return [String, nil] The hash seed to use
    attr_accessor :seed

    # @return [String] Human-readable name for the experiment
    attr_accessor :name

    # @return [String, nil] Id of the current experiment phase
    attr_accessor :phase

    # @return [String, nil] The attribute to use when hash_attribute is missing (requires Sticky Bucketing)
    attr_accessor :fallback_attribute

    # @return [bool, nil] When true, disables sticky bucketing
    attr_accessor :disable_sticky_bucketing

    # @return [integer] Appended to the experiment key for sticky bucketing
    attr_accessor :bucket_version

    # @return [integer] Minimum bucket version required for sticky bucketing
    attr_accessor :min_bucket_version

    # @return [Array<Hash>] Array of prerequisite flags
    attr_accessor :parent_conditions

    def initialize(options = {})
      @key = get_option(options, :key, '').to_s
      @variations = get_option(options, :variations, [])
      @weights = get_option(options, :weights)
      @active = get_option(options, :active, true)
      @coverage = get_option(options, :coverage, 1.0)
      @ranges = get_option(options, :ranges)
      @condition = get_option(options, :condition)
      @namespace = get_option(options, :namespace)
      @force = get_option(options, :force)
      @hash_attribute = get_option(options, :hash_attribute) || get_option(options, :hashAttribute) || 'id'
      @hash_version = get_option(options, :hash_version) || get_option(options, :hashVersion)
      @meta = get_option(options, :meta)
      @filters = get_option(options, :filters)
      @seed = get_option(options, :seed)
      @name = get_option(options, :name)
      @phase = get_option(options, :phase)
      @fallback_attribute = get_option(options, :fallback_attribute) || get_option(options, :fallbackAttribute)
      @disable_sticky_bucketing = get_option(options, :disable_sticky_bucketing, false) || get_option(options, :disableStickyBucketing, false)
      @bucket_version = get_option(options, :bucket_version) || get_option(options, :bucketVersion) || 0
      @min_bucket_version = get_option(options, :min_bucket_version) || get_option(options, :minBucketVersion) || 0
      @parent_conditions = get_option(options, :parent_conditions) || get_option(options, :parentConditions) || []

      return unless @disable_sticky_bucketing

      @fallback_attribute = nil
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
      res['fallbackAttribute'] = @fallback_attribute unless @fallback_attribute.nil?
      res['disableStickyBucketing'] = @disable_sticky_bucketing if @disable_sticky_bucketing
      res['bucketVersion'] = @bucket_version if @bucket_version != 0
      res['minBucketVersion'] = @min_bucket_version if @min_bucket_version != 0
      res['parentConditions'] = @parent_conditions unless @parent_conditions.empty?

      res.compact
    end

    private

    def get_option(hash, key, default = nil)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      default
    end
  end
end
