module Growthbook
  class FeatureResult
    # The assigned value of the feature
    # @return [Any, nil]
    attr_reader :value

    # Whether or not the feature is ON
    # @return [Bool]
    attr_reader :on

    # Whether or not the feature is OFF
    # @return [Bool]
    attr_reader :off

    # The reason the feature was assigned this value
    # @return [String]
    attr_reader :source

    # The experiment used to decide the feature value
    # @return [GrowthBook.Experiment, nil]
    attr_reader :experiment

    # The result of the experiment
    # @return [GrowthBook.ExperimentResult, nil]
    attr_reader :experiment_result

    def initialize(
      value,
      source,
      experiment,
      experiment_result
    )

      @value = value
      @on = value ? true : false
      @off = value ? false : true
      @source = source
      @experiment = experiment
      @experiment_result = experiment_result
    end
  end