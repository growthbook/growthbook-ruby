# frozen_string_literal: true

module Growthbook
  class Context
    attr_accessor :enabled, :url, :qa_mode, :listener
    attr_reader :attributes, :features, :impressions, :forced_variations, :forced_features

    def initialize(options = {})
      @features = {}
      @forced_variations = {}
      @forced_features = {}
      @attributes = {}
      @enabled = true
      @impressions = {}

      options.each do |key, value|
        case key.to_sym
        when :enabled
          @enabled = value
        when :attributes
          self.attributes = value
        when :url
          @url = value
        when :features
          self.features = value
        when :forced_variations, :forcedVariations
          self.forced_variations = value
        when :forced_features
          self.forced_features = value
        when :qa_mode, :qaMode
          @qa_mode = value
        when :listener
          @listener = value
        else
          warn("Unknown context option: #{key}")
        end
      end
    end


    def features=(features)
      @features = {}

      features.each do |k, v|
        # Convert to a Feature object if it's not already
        v = Growthbook::Feature.new(v) unless v.is_a? Growthbook::Feature

        @features[k.to_s] = v
      end
    end

    def attributes=(attrs)
      @attributes = stringify_keys(attrs || {})
    end

    def forced_variations=(forced_variations)
      @forced_variations = stringify_keys(forced_variations || {})
    end

    def forced_features=(forced_features)
      @forced_features = stringify_keys(forced_features || {})
    end

    def eval_feature(key)
      # Forced in the context
      if @forced_features.key?(key.to_s)
        return get_feature_result(@forced_features[key.to_s], 'override') 
      end

      # Return if we can't find the feature definition
      feature = get_feature(key)
      return get_feature_result(nil, 'unknownFeature') unless feature

      feature.rules.each do |rule|
        # Targeting condition
        next if rule.condition && !condition_passes(rule.condition)

        # Rollout or forced value rule
        if rule.is_force?
          unless rule.coverage.nil?
            hash_value = get_attribute(rule.hash_attribute || 'id')
            next if hash_value.length.zero?

            n = Growthbook::Util.hash(hash_value + key)
            next if n > rule.coverage
          end
          return get_feature_result(rule.force, 'force')
        end
        # Experiment rule
        next unless rule.is_experiment?

        exp = rule.to_experiment(key)
        result = run(exp)

        next unless result.in_experiment

        return get_feature_result(result.value, 'experiment', exp, result)
      end

      # Fallback
      get_feature_result(feature.default_value || nil, 'defaultValue')
    end

    def run(exp)
      key = exp.key

      # 1. If experiment doesn't have enough variations, return immediately
      return get_experiment_result(exp) if exp.variations.length < 2

      # 2. If context is disabled, return immediately
      return get_experiment_result(exp) unless @enabled

      # 3. If forced via URL querystring
      if @url
        qsOverride = Util.get_query_string_override(key, @url, exp.variations.length)
        return get_experiment_result(exp, qsOverride) unless qsOverride.nil?
      end

      # 4. If variation is forced in the context, return the forced value
      return get_experiment_result(exp, @forced_variations[key.to_s]) if @forced_variations.key?(key.to_s)

      # 5. Exclude if not active
      return get_experiment_result(exp) unless exp.active

      # 6. Get hash_attribute/value and return if empty
      hash_attribute = exp.hash_attribute || 'id'
      hash_value = get_attribute(hash_attribute)
      return get_experiment_result(exp) if hash_value.length.zero?

      # 7. Exclude if user not in namespace
      return get_experiment_result(exp) if exp.namespace && !Growthbook::Util.in_namespace(hash_value, exp.namespace)

      # 8. Exclude if condition is false
      return get_experiment_result(exp) if exp.condition && !condition_passes(exp.condition)

      # 9. Calculate bucket ranges and choose one
      ranges = Growthbook::Util.get_bucket_ranges(
        exp.variations.length,
        exp.coverage,
        exp.weights
      )
      n = Growthbook::Util.hash(hash_value + key)
      assigned = Growthbook::Util.choose_variation(n, ranges)

      # 10. Return if not in experiment
      return get_experiment_result(exp) if assigned.negative?

      # 11. Experiment has a forced variation
      return get_experiment_result(exp, exp.force) unless exp.force.nil?

      # 12. Exclude if in QA mode
      return get_experiment_result(exp) if @qa_mode

      # 13. Build the result object
      result = get_experiment_result(exp, assigned, true)

      # 14. Fire tracking callback
      track_experiment(exp, result)

      # 15. Return the result
      return result
    end

    def is_on?(key)
      this.eval_feature(key).on
    end

    def is_off?(key)
      this.eval_feature(key).off
    end

    def feature_value(key, fallback=nil)
      value = this.eval_feature(key).value
      value.nil? ? fallback : value
    end

    private

    def stringify_keys(hash)
      new_hash = {}
      hash.each do |key, value|
        new_hash[key.to_s] = value
      end
      return new_hash
    end

    def condition_passes(condition)
      Growthbook::Conditions.eval_condition(@attributes, condition)
    end

    def get_experiment_result(experiment, variation_index = 0, in_experiment = false)
      variation_index = 0 if variation_index.negative? || variation_index >= experiment.variations.length

      hash_attribute = experiment.hash_attribute || 'id'
      hash_value = get_attribute(hash_attribute)

      Growthbook::InlineExperimentResult.new(in_experiment, variation_index,
                                             experiment.variations[variation_index], hash_attribute, hash_value)
    end

    def get_feature_result(value, source, experiment = nil, experiment_result = nil)
      Growthbook::FeatureResult.new(value, source, experiment, experiment_result)
    end

    def get_feature(key)
      return @features[key.to_sym] if @features.key?(key.to_sym)
      return @features[key.to_s] if @features.key?(key.to_s)

      nil
    end

    def get_attribute(key)
      return @attributes[key.to_sym] if @attributes.key?(key.to_sym)
      return @attributes[key.to_s] if @attributes.key?(key.to_s)

      ''
    end

    def track_experiment(experiment, result)
      if @listener && @listener.respond_to?(:on_experiment_viewed)
        @listener.on_experiment_viewed(experiment, result)
      end
      @impressions[experiment.key] = result
    end
  end
end
