# frozen_string_literal: true

module Growthbook
  class LookupResult
    # The first matching experiment
    # @return [Growthbook::Experiment]
    attr_reader :experiment

    # The chosen variation. -1 for "not in experiment", 0 for control, 1 for 1st variation, etc.
    # @return [Integer]
    attr_reader :variation

    # The data tied to the chosen variation
    # @return [Hash]
    attr_reader :data

    # The value of the data key that was used to lookup the experiment
    attr_reader :value

    @forced

    def forced?
      @forced
    end

    def shouldTrack?
      !@forced && @variation >= 0
    end

    def initialize(result, key)
      @experiment = result.experiment
      @variation = result.variation
      @forced = result.forced?

      @data = {}
      if @experiment&.data
        var = @variation.negative? ? 0 : @variation
        @experiment.data.each do |k, v|
          @data[k] = v[var]
        end
      end

      @value = @data[key] || nil
    end
  end
end
