module Growthbook
  class Context
    attr_accessor :enabled
    attr_accessor :attributes
    attr_accessor :url
    attr_accessor :features
    attr_accessor :forcedVariations
    attr_accessor :qaMode
    attr_accessor :trackingCallback

    def initialize(options = {})
      @features = {}
      @forcedVariations = {}
      @attributes = {}

      options.each do |key, value|
        case key.to_sym
        when :enabled
          @enabled = value
        when :attributes
          @attributes = value
        when :url
          @url = value
        when :features
          value.each do |k,v|
            @features[k] = Growthbook::Feature.new(v)
          end
        when :forcedVariations
          @forcedVariations = value
        when :qaMode
          @qaMode = value
        when :trackingCallback
          @trackingCallback = value
        else
          warn("Unknown context option: #{key}")
        end
      end
    end

    def getExperimentResult(experiment, variationIndex = 0, inExperiment = false)
      if variationIndex < 0 || variationIndex >= experiment.variations.length
        variationIndex = 0
      end

      hashAttribute = experiment.hashAttribute || 'id'
      hashValue = @attributes[hashAttribute] || ''

      return Growthbook::InlineExperimentResult.new(inExperiment, variationIndex, experiment.variations[variationIndex], hashAttribute, hashValue)
    end

    def getFeatureResult(value, source, experiment = nil, experiment_result = nil)
      return Growthbook::FeatureResult.new(value, source, experiment, experiment_result)
    end

    def evalFeature(key)
      if !@features.has_key?(key)
        return getFeatureResult(nil, "unknownFeature")
      end

      feature = @features[key]
      feature.rules.each do |rule|
        # Targeting condition
        if rule.condition && !Growthbook::Util.evalCondition(@attributes, rule.condition)
          continue
        end
        # Rollout or forced value rule
        if rule.force != nil
          if rule.coverage != nil
            hashValue = @attributes[rule.hashAttribute || "id"]
            if !hashValue
              continue
            end
            n = Growthbook::Util.hash(hashValue + key)
            if n > rule.coverage
              continue
            end
          end
          return getFeatureResult(rule.force, "force")
        end
        # Experiment rule
        if rule.variations
          exp = rule.toExperiment(key)
          result = run(exp)

          if !result.in_experiment
            continue
          end

          return getFeatureResult(result.value, "experiment", exp, result)
        end
      end

      # Fallback
      return getFeatureResult(feature.default_value || nil, "defaultValue")
    end

    def _run(exp)
      key = exp["key"]

      # 1. If experiment doesn't have enough variations, return immediately
      return getExperimentResult(exp) if exp["variations"].length < 2

      # 2. If context is disabled, return immediately
      return getExperimentResult(exp) if !@enabled

      # 3. If forced via URL querystring
      if @url
        qsOverride = Util.getQueryStringOverride(key, @url)
        return getExperimentResult(exp, qsOverride) if qsOverride != nil
      end

      # 4. If variation is forced in the context, return the forced value
      if @forcedVariations.has_key?(key)
        return getExperimentResult(exp, @forcedVariations[key])
      end

      # 5. Exclude if not active
      return getExperimentResult(exp) if !exp["active"]

      # 6. Get hashAttribute/value and return if empty
      hashAttribute, hashValue = getHashAttribute(exp["hashAttribute"])
      return getExperimentResult(exp) if !hashValue.length

      # 7. Exclude if user not in namespace
      if exp.has_key?("namespace")
        return getExperimentResult(exp) if !Growthbook::Util.inNamespace(hashValue, exp["namespace"])
      end

      # 8. Exclude if condition is false
      if exp.has_key?("condition")
        return getExperimentResult(exp) if !conditionPasses(exp["condition"])
      end

      # 9. Calculate bucket ranges and choose one
      ranges = Growthbook::Util.getBucketRanges(
        exp["variations"].length,
        exp["coverage"],
        exp["weights"]
      )
      n = Growthbook::Util.hash(hashValue + key)
      assigned = Growthbook::Util.chooseVariationNew(n, ranges)

      # 10. Return if not in experiment
      return getExperimentResult(exp) if assigned < 0

      # 11. Experiment has a forced variation
      if exp.has_key?("force")
        return getExperimentResult(exp, exp["force"])
      end

      # 12. Exclude if in QA mode
      return getExperimentResult(exp) if @qaMode

      # 13. Build the result object
      result = getExperimentResult(exp, assigned, true)

      # 14. Fire tracking callback
      # TODO

      # 15. Return the result
      return result
    end

    def conditionPasses(condition)
      return Growthbook::Conditions.evalCondition(@attributes, condition)
    end

    def isOn(key)
      return this.evalFeature(key).on
    end

    def isOff(key)
      return this.evalFeature(key).off
    end

    def getFeatureValue(key, fallback)
      value = this.evalFeature(key).value
      return value == nil ? fallback : value
    end
  end
end