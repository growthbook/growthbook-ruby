# frozen_string_literal: true

module Growthbook
  # Result of a feature evaluation
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
    # @return [Growthbook::InlineExperiment, nil]
    attr_reader :experiment

    # The result of the experiment
    # @return [Growthbook::InlineExperimentResult, nil]
    attr_reader :experiment_result

    # The id of the rule (if any) that was used to assign the value
    # @return [String]
    attr_reader :rule_id

    def initialize(
      value,
      source,
      experiment,
      experiment_result,
      rule_id = ''
    )

      on = !value.nil? && value != 0 && value != '' && value != false

      @value = value
      @on = on
      @off = !on
      @source = source
      @experiment = experiment
      @experiment_result = experiment_result
      @rule_id = rule_id || ''
    end

    def to_json(*_args)
      json = {}
      json['on'] = @on
      json['off'] = @off
      json['value'] = @value
      json['source'] = @source
      json['ruleId'] = @rule_id

      if @experiment
        json['experiment'] = @experiment.to_json
        json['experimentResult'] = @experiment_result.to_json
      end

      json
    end
  end
end
