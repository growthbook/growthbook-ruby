module Growthbook
  class User
    attr_accessor :id
    attr_accessor :anonId
    
    @attributes = []
    @client
    @attributeMap = {}

    def initialize(anonId, id, attributes, client)
      @anonId = anonId
      @id = id
      @attributes = attributes
      @client = client
      updateAttributeMap
    end

    def experiment(experiment)
      # If experiments are disabled globally
      return Growthbook::Result.new unless @client.config.enabled

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
      return Growthbook::Result.new(Growthbook::Experiment.new(id, 2), -1) unless experiment

      # User missing required user id type
      userId = experiment.anon ? @anonId : @id
      return Growthbook::Result.new(experiment) unless userId

      # Experiment has targeting rules, check if user passes
      if experiment.targeting
        return Growthbook::Result.new(experiment) unless isTargeted(experiment.targeting)
      end

      # Choose a variation for the user
      variation = Growthbook::Util.chooseVariation(userId, experiment)
      return Growthbook::Result.new(experiment, variation)
    end

    def lookupByDataKey(key)
      @client.experiments.each do |exp|
        if exp.data && exp.data.key?(key)
          ret = experiment(exp)
          if ret.variation >= 0
            return Growthbook::LookupResult.fromResult(ret, key)
          end
        end
      end

      return Growthbook::LookupResult.new
    end

    private

    def flattenUserValues(prefix, val)
      if val.is_a? Hash
        ret = []
        val.each do |v, k|
          ret.concat(flattenUserValues(prefix ? prefix + "." + k : k, v))
        end
        return ret
      end

      if val.is_a? Array
        val = val.join ","
      elsif val.is_a? Boolean
        val = val ? "true" : "false"
      end

      return [
        {
          "k" => prefix,
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
      rules.each do |rule|
        parts = rule.split(" ", 3)
        
        if parts.len == 3
          key = parts[0].trim
          actual = @attributeMap[key] || ""
          return false if Growthbook::Util.checkRule(actual, parts[1].trim, parts[2].trim)
        end
      end

      return true
    end
  end
end