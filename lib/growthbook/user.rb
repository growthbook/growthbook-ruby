# frozen_string_literal: true

require 'set'

module Growthbook
  class User
    # @returns [String, nil]
    attr_accessor :id

    # @returns [String, nil]
    attr_accessor :anonId

    # @returns [Hash, nil]
    attr_reader :attributes

    # @returns [Array<Growthbook::ExperimentResult>]
    attr_reader :resultsToTrack

    @client
    @attributeMap = {}
    @experimentsTracked

    def initialize(anonId, id, attributes, client)
      @anonId = anonId
      @id = id
      @attributes = attributes
      @client = client
      updateAttributeMap

      @resultsToTrack = []
      @experimentsTracked = Set[]
    end

    # Set the user attributes
    #
    # @params attributes [Hash, nil] Any user attributes you want to use for experiment targeting
    #    Values can be any type, even nested arrays and hashes
    def attributes=(attributes)
      @attributes = attributes
      updateAttributeMap
    end

    # Run an experiment on this user
    # @param experiment [Growthbook::Experiment, String] If string, will lookup the experiment by id in the client
    # @return [Growthbook::ExperimentResult]
    def experiment(experiment)
      # If experiments are disabled globally
      return getExperimentResult unless @client.enabled

      # Make sure experiment is always an object (or nil)
      id = ''
      if experiment.is_a? String
        id = experiment
        experiment = @client.getExperiment(id)
      else
        id = experiment.id
        override = @client.getExperiment(id)
        experiment = override if override
      end

      # No experiment found
      return getExperimentResult unless experiment

      # User missing required user id type
      userId = experiment.anon ? @anonId : @id
      return getExperimentResult(experiment) unless userId

      # Experiment has targeting rules, check if user passes
      return getExperimentResult(experiment) if experiment.targeting && !isTargeted(experiment.targeting)

      # Experiment has a specific variation forced
      return getExperimentResult(experiment, experiment.force, true) unless experiment.force.nil?

      # Choose a variation for the user
      variation = Growthbook::Util.chooseVariation(userId, experiment)
      result = getExperimentResult(experiment, variation)

      # Add to the list of experiments that should be tracked in analytics
      if result.shouldTrack? && !@experimentsTracked.include?(experiment.id)
        @experimentsTracked << experiment.id
        @resultsToTrack << result
      end

      result
    end

    # Run the first matching experiment that defines variation data for the requested key
    # @param key [String, Symbol] The key to look up
    # @return [Growthbook::LookupResult, nil] If nil, no matching experiments found
    def lookupByDataKey(key)
      @client.experiments.each do |exp|
        next unless exp.data&.key?(key)

        ret = experiment(exp)
        return Growthbook::LookupResult.new(ret, key) if ret.variation >= 0
      end

      nil
    end

    private

    def getExperimentResult(experiment = nil, variation = -1, forced = false)
      Growthbook::ExperimentResult.new(self, experiment, variation, forced)
    end

    def flattenUserValues(prefix, val)
      return [] if val.nil?

      if val.is_a? Hash
        ret = []
        val.each do |k, v|
          ret.concat(flattenUserValues(prefix.length.positive? ? "#{prefix}.#{k}" : k.to_s, v))
        end
        return ret
      end

      case val
      when Array
        val = val.join ','
      when !val.nil?
        val = val ? 'true' : 'false'
      end

      [
        {
          'k' => prefix.to_s,
          'v' => val.to_s
        }
      ]
    end

    def updateAttributeMap
      @attributeMap = {}
      flat = flattenUserValues('', @attributes)
      flat.each do |item|
        @attributeMap[item['k']] = item['v']
      end
    end

    def isTargeted(rules)
      pass = true
      rules.each do |rule|
        parts = rule.split(' ', 3)
        next unless parts.length == 3

        key = parts[0].strip
        actual = @attributeMap[key] || ''
        unless Growthbook::Util.checkRule(actual, parts[1].strip, parts[2].strip)
          pass = false
          break
        end
      end

      pass
    end
  end
end
