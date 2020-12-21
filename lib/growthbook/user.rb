module Growthbook
  class User
    # @returns [String, nil]
    attr_accessor :id

    # @returns [String, nil]
    attr_accessor :anonId

    # @returns [Hash, nil]
    attr_reader :attributes
    
    @client
    @attributeMap = {}

    def initialize(anonId, id, attributes, client)
      @anonId = anonId
      @id = id
      @attributes = attributes
      @client = client
      updateAttributeMap
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
      return Growthbook::ExperimentResult.new unless @client.enabled

      # Make sure experiment is always an object (or nil)
      id = ""
      if experiment.is_a? String
        id = experiment
        experiment = @client.getExperiment(id)
      else
        id = experiment.id
        override = @client.getExperiment(id)
        experiment = override if override
      end

      # No experiment found
      return Growthbook::ExperimentResult.new unless experiment

      # User missing required user id type
      userId = experiment.anon ? @anonId : @id
      if !userId
        return Growthbook::ExperimentResult.new(experiment)
      end

      # Experiment has targeting rules, check if user passes
      if experiment.targeting
        return Growthbook::ExperimentResult.new(experiment) unless isTargeted(experiment.targeting)
      end

      # Experiment has a specific variation forced
      if experiment.force != nil
        return Growthbook::ExperimentResult.new(experiment, experiment.force, true)
      end

      # Choose a variation for the user
      variation = Growthbook::Util.chooseVariation(userId, experiment)
      return Growthbook::ExperimentResult.new(experiment, variation)
    end

    # Run the first matching experiment that defines variation data for the requested key
    # @param key [String, Symbol] The key to look up
    # @return [Growthbook::LookupResult, nil] If nil, no matching experiments found
    def lookupByDataKey(key)
      @client.experiments.each do |exp|
        if exp.data && exp.data.key?(key)
          ret = experiment(exp)
          if ret.variation >= 0
            return Growthbook::LookupResult.new(ret, key)
          end
        end
      end

      return nil
    end

    private

    def flattenUserValues(prefix, val)
      if val.nil? 
        return []
      end
      
      if val.is_a? Hash
        ret = []
        val.each do |k, v|
          ret.concat(flattenUserValues(prefix.length>0 ? prefix.to_s + "." + k.to_s : k.to_s, v))
        end
        return ret
      end

      if val.is_a? Array
        val = val.join ","
      elsif !!val == val
        val = val ? "true" : "false"
      end

      return [
        {
          "k" => prefix.to_s,
          "v" => val.to_s
        }
      ]
    end

    def updateAttributeMap
      @attributeMap = {}
      flat = flattenUserValues("", @attributes)
      flat.each do |item|
        @attributeMap[item["k"]] = item["v"]
      end
    end

    def isTargeted(rules)
      pass = true
      rules.each do |rule|
        parts = rule.split(" ", 3)
        if parts.length == 3
          key = parts[0].strip
          actual = @attributeMap[key] || ""
          if !Growthbook::Util.checkRule(actual, parts[1].strip, parts[2].strip)
            pass = false
            break
          end
        end
      end

      return pass
    end
  end
end