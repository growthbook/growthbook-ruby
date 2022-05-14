# frozen_string_literal: true

module Growthbook
  class InlineExperimentResult
    # Whether or not the user is in the experiment
    # @return [Bool]
    attr_reader :in_experiment

    # The array index of the assigned variation
    # @return [Integer]
    attr_reader :variationId

    # The assigned variation value
    # @return [Any]
    attr_reader :value

    # The attribute used to split traffic
    # @return [String]
    attr_reader :hashAttribute

    # The value of the hashAttribute
    # @return [String]
    attr_reader :hashValue

    def initialize(
      inExperiment,
      variationId,
      value,
      hashAttribute,
      hashValue
    )

      @inExperiment = inExperiment
      @variationId = variationId
      @value = value
      @hashAttribute = hashAttribute
      @hashValue = hashValue
    end
  end
end
