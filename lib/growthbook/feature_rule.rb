# frozen_string_literal: true

module Growthbook
  # Internal class that overrides the default value of a Feature based on a set of requirements.
  class FeatureRule
    # @return [Hash , nil] Optional targeting condition
    attr_reader :condition

    # @return [Float , nil] What percent of users should be included in the experiment (between 0 and 1, inclusive)
    attr_reader :coverage

    # @return [T , nil] Immediately force a specific value (ignore every other option besides condition and coverage)
    attr_reader :force

    # @return [T[] , nil] Run an experiment (A/B test) and randomly choose between these variations
    attr_reader :variations

    # @return [String , nil] The globally unique tracking key for the experiment (default to the feature key)
    attr_reader :key

    # @return [Float[] , nil] How to weight traffic between variations. Must add to 1.
    attr_reader :weights

    # @return [String , nil] Adds the experiment to a namespace
    attr_reader :namespace

    # @return [String , nil] What user attribute should be used to assign variations (defaults to id)
    attr_reader :hash_attribute

    # @return [Integer , nil] The hash version to use (default to 1)
    attr_reader :hash_version

    # @return [BucketRange , nil] A more precise version of coverage
    attr_reader :range

    # @return [BucketRanges[] , nil] Ranges for experiment variations
    attr_reader :ranges

    # @return [VariationMeta[] , nil] Meta info about the experiment variations
    attr_reader :meta

    # @return [Filter[] , nil] Array of filters to apply to the rule
    attr_reader :filters

    # @return [String , nil]  Seed to use for hashing
    attr_reader :seed

    # @return [String , nil] Human-readable name for the experiment
    attr_reader :name

    # @return [String , nil] The phase id of the experiment
    attr_reader :phase

    # @return [TrackData[] , nil] Array of tracking calls to fire
    attr_reader :tracks

    # @return [String, nil] The attribute to use when hash_attribute is missing (requires Sticky Bucketing)
    attr_accessor :fallback_attribute

    # @return [String, nil] When true, disables sticky bucketing
    attr_accessor :disable_sticky_bucketing

    # @return [integer] Appended to the experiment key for sticky bucketing
    attr_accessor :bucket_version

    # @return [integer] Minimum bucket version required for sticky bucketing
    attr_accessor :min_bucket_version

    # @return [Array<Hash>] Array of prerequisite flags
    attr_accessor :parent_conditions

    def initialize(rule)
      @coverage = get_option(rule, :coverage)
      @force = get_option(rule, :force)
      @variations = get_option(rule, :variations)
      @key = get_option(rule, :key)
      @weights = get_option(rule, :weights)
      @namespace = get_option(rule, :namespace)
      @hash_attribute = get_option(rule, :hash_attribute) || get_option(rule, :hashAttribute)
      @hash_version = get_option(rule, :hash_version) || get_option(rule, :hashVersion)
      @range = get_option(rule, :range)
      @ranges = get_option(rule, :ranges)
      @meta = get_option(rule, :meta)
      @filters = get_option(rule, :filters)
      @seed = get_option(rule, :seed)
      @name = get_option(rule, :name)
      @phase = get_option(rule, :phase)
      @tracks = get_option(rule, :tracks)

      cond = get_option(rule, :condition)
      @condition = Growthbook::Conditions.parse_condition(cond) unless cond.nil?

      @fallback_attribute = get_option(rule, :fallback_attribute) || get_option(rule, :fallbackAttribute)
      @disable_sticky_bucketing = get_option(rule, :disable_sticky_bucketing, false) || get_option(rule, :disableStickyBucketing, false)
      @bucket_version = get_option(rule, :bucket_version, 0) || get_option(rule, :bucketVersion, 0)
      @min_bucket_version = get_option(rule, :min_bucket_version, 0) || get_option(rule, :minBucketVersion, 0)
      @parent_conditions = get_option(rule, :parent_conditions, []) || get_option(rule, :parentConditions, [])

      if @disable_sticky_bucketing
        @fallback_attribute = nil
      end
    end

    # @return [Growthbook::InlineExperiment, nil]
    def to_experiment(feature_key)
      return nil unless @variations

      Growthbook::InlineExperiment.new(
        key: @key || feature_key,
        variations: @variations,
        condition: @condition,
        coverage: @coverage,
        weights: @weights,
        hash_attribute: @hash_attribute,
        hash_version: @hash_version,
        namespace: @namespace,
        meta: @meta,
        ranges: @ranges,
        filters: @filters,
        name: @name,
        phase: @phase,
        seed: @seed,
        fallback_attribute: @fallback_attribute,
        disable_sticky_bucketing: @disable_sticky_bucketing,
        bucket_version: @bucket_version,
        min_bucket_version: @min_bucket_version
      )
    end

    def experiment?
      return false if @variations.nil?

      !@variations&.empty?
    end

    def force?
      !experiment? && !@force.nil?
    end

    def to_json(*_args)
      {
        'condition'     => @condition,
        'coverage'      => @coverage,
        'force'         => @force,
        'variations'    => @variations,
        'key'           => @key,
        'weights'       => @weights,
        'namespace'     => @namespace,
        'hashAttribute' => @hash_attribute,
        'range'         => @range,
        'ranges'        => @ranges,
        'meta'          => @meta,
        'filters'       => @filters,
        'seed'          => @seed,
        'name'          => @name,
        'phase'         => @phase,
        'tracks'        => @tracks,
        'fallbackAttribute' => @fallback_attribute,
        'disableStickyBucketing' => @disable_sticky_bucketing,
        'bucketVersion' => @bucket_version,
        'minBucketVersion' => @min_bucket_version,
        'parentConditions' => @parent_conditions
      }.compact
    end

    private

    def get_option(hash, key, default = nil)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      default
    end
  end
end
