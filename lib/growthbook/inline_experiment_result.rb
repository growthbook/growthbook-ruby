# frozen_string_literal: true

module Growthbook
  # Result of running an experiment.
  class InlineExperimentResult
    # The array index of the assigned variation
    # @return [Integer]
    attr_reader :variation_id

    # The assigned variation value
    # @return [Any]
    attr_reader :value

    # The attribute used to split traffic
    # @return [String]
    attr_reader :hash_attribute

    # The value of the hashAttribute
    # @return [String]
    attr_reader :hash_value

    attr_reader :feature_id

    def initialize(
      hash_used:,
      in_experiment:,
      variation_id:,
      value:,
      hash_attribute:,
      hash_value:,
      feature_id:
    )
      @hash_used = hash_used
      @in_experiment = in_experiment
      @variation_id = variation_id
      @value = value
      @hash_attribute = hash_attribute
      @hash_value = hash_value
      @feature_id = feature_id
    end

    # If the variation was randomly assigned based on user attribute hashes
    # @return [Bool]
    def hash_used?
      @hash_used
    end

    # Whether or not the user is in the experiment
    # @return [Bool]
    def in_experiment?
      @in_experiment
    end

    def to_json(*_args)
      res = {}
      res['inExperiment'] = @in_experiment
      res['hashUsed'] = @hash_used
      res['variationId'] = @variation_id
      res['value'] = @value
      res['hashAttribute'] = @hash_attribute
      res['hashValue'] = @hash_value
      res['featureId'] = @feature_id.to_s
      res
    end
  end
end
