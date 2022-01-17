module Growthbook
  class Client
    # @returns [Boolean]
    attr_accessor :enabled

    # @returns [Hash]
    attr_accessor :attributes

    # @returns [Hash]
    attr_accessor :features
    
    # @returns [Array<Growthbook::Experiment>]
    attr_accessor :experiments

    # @param config [Hash]
    # @option config [Boolean] :qaMode (false) Set to true to disable random assignment
    # @option config [Boolean] :enabled (true) Set to false to disable all experiments
    # @option config [String] :url ("") The URL of the current request
    # @option config [Hash] :attributes ({}) User targeting attributes 
    # @option config [Hash] :features ({}) Feature definitions
    def initialize(config = {})
      @enabled = config.has_key?(:enabled) ? config[:enabled] : true
      @attributes = config[:attributes] || {}
      @features = config[:features] || {}

      @url = ""
      @forcedVariations = {}
      @qaMode = config.has_key?(:qaMode) ? config[:qaMode] : false

      @resultsToTrack = []

      # Deprecated
      @experiments = config[:experiments] || []
    end


    # Evaluate a feature
    # @param key [String] The feature key
    def feature(key)
      feature = @features[key] || nil
      # If feature is not defined
      return getFeatureResult(nil, "unknownFeature") if feature == nil
      
      # Use defaultValue if there are no rules
      return getFeatureResult(feature["defaultValue"], "defaultValue") if !feature["rules"]

      feature["rules"].each do |rule|
        if rule["condition"]
          if !Growthbook::Mongrule.evalCondition(@attributes, rule["condition"])
            next
          end
        end
        if rule.has_key? "force"
          if rule.has_key? "coverage"
            hashAttribute, hashValue = getHashAttribute(rule.hashAttribute)
            if !hashValue
              next
            end
            n = Growthbook::Util.hash(hashValue + key)
            if n > rule["coverage"]
              next
            end
          end
          return getFeatureResult(rule["force"], "force")
        end

        # Covert rule to experiment
        exp = {}
        exp["variations"] = rule["variations"]
        exp["key"] = rule.has_key?("trackingKey") ? rule["trackingKey"] : key
        
        if rule.has_key?("coverage")
          exp["coverage"] = rule["coverage"]
        end
        if rule.has_key?("weights")
          exp["weights"] = rule["weights"]
        end
        if rule.has_key?("hashAttribute")
          exp["hashAttribute"] = rule["hashAttribute"]
        end
        if rule.has_key?("namespace")
          exp["namespace"] = rule["namespace"]
        end

        # Run the experiment
        result = run(exp)

        if !result.inExperiment
          next
        end

        return getFeatureResult(result.value, "experiment", exp, result)
      end

      return getFeatureResult(feature["defaultValue"], "defaultValue")
    end

    def run(exp)
      return _run(exp)
    end

    # Deprecated
    # Look up a pre-configured experiment by id
    # 
    # @param id [String] The experiment id to look up
    # @return [Growthbook::Experiment, nil] the experiment object or nil if not found
    def getExperiment(id)
      match = nil;
      @experiments.each do |exp|
        if exp.id == id
          match = exp
          break
        end
      end
      return match
    end

    # Deprecated
    # Get a User object you can run experiments against
    # 
    # @param params [Hash]
    # @option params [String, nil] :id The logged-in user id
    # @option params [String, nil] :anonId The anonymous id (session id, ip address, cookie, etc.)
    # @option params [Hash, nil] :attributes Any user attributes you want to use for experiment targeting
    #    Values can be any type, even nested arrays and hashes
    # @return [Growthbook::User] the User object
    def user(params = {})
      Growthbook::User.new(
        params[:anonId] || nil,
        params[:id] || nil,
        params[:attributes] || nil,
        self
      )
    end

    # Deprecated
    def importExperimentsHash(experimentsHash = {})
      @experiments = []
      experimentsHash.each do |id, data|
        variations = data["variations"]

        options = {}
        options[:coverage] = data["coverage"] if data.has_key?("coverage")
        options[:weights] = data["weights"] if data.has_key?("weights")
        options[:force] = data["force"] if data.has_key?("force")
        options[:anon] = data["anon"] if data.has_key?("anon")
        options[:targeting] = data["targeting"] if data.has_key?("targeting")
        options[:data] = data["data"] if data.has_key?("data")

        @experiments << Growthbook::Experiment.new(id, variations, options)
      end
    end

    private

    def getFeatureResult(value, source, experiment = nil)
      ret = {}
      ret[:value] = value
      ret[:source] = source
      ret[:on] = !!value
      ret[:off] = !value

      if experiment
        ret[:experiment] = experiment
      end

      return ret
    end

    def getHashAttribute(hashAttribute)
      hashAttribute = "id" if !hashAttribute
      hashValue = ""
      if @attributes[hashAttribute]
        hashValue = @attributes[hashAttribute]
      end

      return hashAttribute, hashValue
    end

    def getExperimentResult(exp, varIndex = 0, inExperiment = false)
      if varIndex < 0 || varIndex >= exp["variations"].length
        varIndex = 0
      end

      hashAttribute, hashValue = getHashAttribute(exp["hashAttribute"])

      ret = {}
      ret[:inExperiment] = inExperiment
      ret[:variationId] = varIndex
      ret[:value] = exp["variations"][varIndex]
      ret[:hashAttribute] = hashAttribute
      ret[:hashValue] = hashValue

      return ret
    end

    def _run(exp)
      key = exp["key"]

      # 1. If experiment doesn't have enough variations, return immediately
      return getExperimentResult(exp) if exp["variations"].length < 2

      # 2. If context is disabled, return immediately
      return getExperimentResult(exp) if !@enabled

      # 5. If variation is forced in the client, return the forced value
      if @forcedVariations.has_key?(key)
        return getExperimentResult(exp, @forcedVariations[key])
      end

      # 6. Exclude if not active
      return getExperimentResult(exp) if !exp["active"]

      # 7. Get hashAttribute/value and return if empty
      hashAttribute, hashValue = getHashAttribute(exp["hashAttribute"])
      return getExperimentResult(exp) if !hashValue.length

      # 8. Exclude if user not in namespace
      if exp.has_key?("namespace")
        return getExperimentResult(exp) if !Growthbook::Util.inNamespace(hashValue, exp["namespace"])
      end

      # 10. Exclude if condition is false
      if exp.has_key?("condition")
        return getExperimentResult(exp) if !conditionPasses(exp["condition"])
      end

      # 13. Get bucket ranges
      ranges = Growthbook::Util.getBucketRanges(
        exp["variations"].length,
        exp["coverage"],
        exp["weights"]
      )

      # 14. Compute hash
      n = Growthbook::Util.hash(hashValue + key)

      # 15. Assign a variation
      assigned = Growthbook::Util.chooseVariation(n, ranges)

      # 16. Return if not in experiment
      return getExperimentResult(exp) if assigned < 0

      # 17. Experiment has a forced variation
      if exp.has_key?("force")
        return getExperimentResult(exp, exp["force"])
      end

      # 18. Exclude if in QA mode
      return getExperimentResult(exp) if @qaMode

      # 20. Fire tracking callback
      result = getExperimentResult(exp, assigned, true)
      # TODO

      # 21. Return the result
      return result
    end

    def conditionPasses(condition)
      return Growthbook::Mongrule.evalCondition(@attributes, condition)
    end
  end
end