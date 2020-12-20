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

    def attributes=(attributes)
      @attributes = attributes
      updateAttributeMap
    end

    def experiment(experiment)
      # If experiments are disabled globally
      return getResult unless @client.enabled

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
      return getResult(Growthbook::Experiment.new(id, 2)) unless experiment

      # User missing required user id type
      userId = experiment.anon ? @anonId : @id
      if !userId
        return getResult(experiment)
      end

      # Experiment has targeting rules, check if user passes
      if experiment.targeting
        return getResult(experiment) unless isTargeted(experiment.targeting)
      end

      # Choose a variation for the user
      variation = Growthbook::Util.chooseVariation(userId, experiment)
      return getResult(experiment, variation)
    end

    def lookupByDataKey(key)
      @client.experiments.each do |exp|
        if exp.data && exp.data.key?(key)
          ret = experiment(exp)
          if ret[:variation] >= 0
            return getLookupResult(ret, key)
          end
        end
      end

      return nil
    end

    private

    def getResult(experiment=nil, variation=-1)
      data = {}
      if experiment && experiment.data
        var = variation <0 ? 0 : variation
        experiment.data.each do |k, v|
          data[k] = v[var] || v[0]
        end
      end
      
      return {
        :variation => variation,
        :experiment => experiment,
        :data => data
      }
    end
    def getLookupResult(result, key)
      value = result[:data][key]

      return {
        :variation => result[:variation],
        :experiment => result[:experiment],
        :data => result[:data],
        :value => value
      }
    end

    def flattenUserValues(prefix, val)
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