# frozen_string_literal: true

module Growthbook
  class InlineExperimentResult
    # Whether or not the user is in the experiment
    # @return [Bool]
    attr_reader :in_experiment

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

    def initialize(
      in_experiment,
      variation_id,
      value,
      hash_attribute,
      hash_value
    )

      @in_experiment = in_experiment
      @variation_id = variation_id
      @value = value
      @hash_attribute = hash_attribute
      @hash_value = hash_value
    end

    def to_json(*_args)
      res = {}
      res['inExperiment'] = @in_experiment
      res['variationId'] = @variation_id
      res['value'] = @value
      res['hashAttribute'] = @hash_attribute
      res['hashValue'] = @hash_value
      res
    end
  end
end
