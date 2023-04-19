# frozen_string_literal: true

require 'set'

module Growthbook
  # @deprecated
  # Internal use only
  class User
    # @return [String, nil]
    attr_accessor :id

    # @return [String, nil]
    attr_accessor :anon_id

    # @return [Hash, nil]
    attr_reader :attributes

    # @return [Array<Growthbook::ExperimentResult>]
    attr_reader :results_to_track

    @client = nil
    @attribute_map = {}
    @experiments_tracked = Set[]

    def initialize(anon_id, id, attributes, client)
      @anon_id = anon_id
      @id = id
      @attributes = attributes
      @client = client
      update_attribute_map

      @results_to_track = []
      @experiments_tracked = Set[]
    end

    # Set the user attributes
    #
    # @param attributes [Hash, nil] Any user attributes you want to use for experiment targeting
    #    Values can be any type, even nested arrays and hashes
    def attributes=(attributes)
      @attributes = attributes
      update_attribute_map
    end

    # Run an experiment on this user
    # @param experiment [Growthbook::Experiment, String] If string, will lookup the experiment by id in the client
    # @return [Growthbook::ExperimentResult]
    def experiment(experiment)
      # If experiments are disabled globally
      return get_experiment_result unless @client.enabled

      # Make sure experiment is always an object (or nil)
      if experiment.is_a? String
        id = experiment
        experiment = @client.get_experiment(id)
      else
        id = experiment.id
        override = @client.get_experiment(id)
        experiment = override if override
      end

      # No experiment found
      return get_experiment_result unless experiment

      # User missing required user id type
      user_id = experiment.anon ? @anon_id : @id
      return get_experiment_result(experiment) unless user_id

      # Experiment has targeting rules, check if user passes
      return get_experiment_result(experiment) if experiment.targeting && !targeted?(experiment.targeting)

      # Experiment has a specific variation forced
      return get_experiment_result(experiment, experiment.force, forced: true) unless experiment.force.nil?

      # Choose a variation for the user
      variation = Growthbook::Util.choose_variation_for_user(user_id, experiment)
      result = get_experiment_result(experiment, variation)

      # Add to the list of experiments that should be tracked in analytics
      if result.should_track? && !@experiments_tracked.include?(experiment.id)
        @experiments_tracked << experiment.id
        @results_to_track << result
      end

      result
    end

    # Run the first matching experiment that defines variation data for the requested key
    # @param key [String, Symbol] The key to look up
    # @return [Growthbook::LookupResult, nil] If nil, no matching experiments found
    def look_up_by_data_key(key)
      @client.experiments.each do |exp|
        next unless exp.data&.key?(key)

        ret = experiment(exp)
        return Growthbook::LookupResult.new(ret, key) if ret.variation >= 0
      end

      nil
    end

    private

    def get_experiment_result(experiment = nil, variation = -1, forced: false)
      Growthbook::ExperimentResult.new(self, experiment, variation, forced: forced)
    end

    def flatten_user_values(prefix, val)
      return [] if val.nil?

      if val.is_a? Hash
        ret = []
        val.each do |k, v|
          ret.concat(flatten_user_values(prefix.length.positive? ? "#{prefix}.#{k}" : k.to_s, v))
        end
        return ret
      end

      if val.is_a? Array
        val = val.join ','
      elsif !val.nil? == val
        val = val ? 'true' : 'false'
      end

      [
        {
          'k' => prefix.to_s,
          'v' => val.to_s
        }
      ]
    end

    def update_attribute_map
      @attribute_map = {}
      flat = flatten_user_values('', @attributes)
      flat.each do |item|
        @attribute_map[item['k']] = item['v']
      end
    end

    def targeted?(rules)
      pass = true
      rules.each do |rule|
        parts = rule.split(' ', 3)
        next unless parts.length == 3

        key = parts[0].strip
        actual = @attribute_map[key] || ''
        unless Growthbook::Util.check_rule(actual, parts[1].strip, parts[2].strip)
          pass = false
          break
        end
      end

      pass
    end
  end
end
