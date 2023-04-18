# frozen_string_literal: true

module Growthbook
  class InlineExperimentResult
    # @return [Boolean] Whether or not the user is part of the experiment
    attr_reader :in_experiment

    # @return [Integer] The array index of the assigned variation
    attr_reader :variation_id

    # @return [Any] The array value of the assigned variation
    attr_reader :value

    # @return [Bool] If a hash was used to assign a variation
    attr_reader :hash_used

    # @return [String] The user attribute used to assign a variation
    attr_reader :hash_attribute

    # @return [String] The value of that attribute
    attr_reader :hash_value

    # @return [String, nil] The id of the feature (if any) that the experiment came from
    attr_reader :feature_id

    # @return [String] The unique key for the assigned variation
    attr_reader :key

    # @return [Float] The hash value used to assign a variation (float from 0 to 1)
    attr_reader :bucket

    # @return [String , nil] Human-readable name for the experiment
    attr_reader :name

    # @return [Boolean]  Used for holdout groups
    attr_accessor :passthrough

    def initialize(options = {})
      @key = options[:key]
      @in_experiment = options[:in_experiment]
      @variation_id = options[:variation_id]
      @value = options[:value]
      @hash_used = options[:hash_used]
      @hash_attribute = options[:hash_attribute]
      @hash_value = options[:hash_value]
      @feature_id = options[:feature_id]
      @bucket = options[:bucket]
      @name = options[:name]
      @passthrough = options[:passthrough]
    end

    def to_json(*_args)
      {
        'inExperiment' => @in_experiment,
        'variationId' => @variation_id,
        'value' => @value,
        'hashUsed' => @hash_used,
        'hashAttribute' => @hash_attribute,
        'hashValue' => @hash_value,
        'featureId' => @feature_id.to_s,
        'key' => @key.to_s,
        'bucket' => @bucket,
        'name' => @name,
        'passthrough' => @passthrough
      }.compact
    end
  end
end
