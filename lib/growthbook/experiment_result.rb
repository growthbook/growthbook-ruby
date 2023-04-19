# frozen_string_literal: true

module Growthbook
  # @deprecated
  # Internal use only
  class ExperimentResult
    # The experiment that was performed
    # @return [Growthbook::Experiment, nil] If nil, then the experiment with the required id could not be found
    attr_reader :experiment

    # The user that was experimented on
    # @return [Growthbook::User]
    attr_reader :user

    # The chosen variation. -1 for "not in experiment", 0 for control, 1 for 1st variation, etc.
    # @return [Integer]
    attr_reader :variation

    # The data tied to the chosen variation
    # @return [Hash]
    attr_reader :data

    @forced = false

    def forced?
      @forced
    end

    def should_track?
      !@forced && @variation >= 0
    end

    def initialize(_user = nil, experiment = nil, variation = -1, forced: false)
      @experiment = experiment
      @variation = variation
      @forced = forced

      @data = {}
      return unless experiment&.data

      var = [variation, 0].max
      experiment.data.each do |k, v|
        @data[k] = v[var]
      end
    end
  end
end