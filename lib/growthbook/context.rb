# frozen_string_literal: true

module Growthbook
  # Context object passed into the GrowthBook constructor.
  class Context
    # @return [true, false] Switch to globally disable all experiments. Default true.
    attr_accessor :enabled

    # @return [String] The URL of the current page
    attr_accessor :url

    # @return [true, false, nil] If true, random assignment is disabled and only explicitly forced variations are used.
    attr_accessor :qa_mode

    # @return [Growthbook::TrackingCallback] An object that responds to `on_experiment_viewed(GrowthBook::InlineExperiment, GrowthBook::InlineExperimentResult)`
    attr_accessor :listener

    # @return [Hash] Map of user attributes that are used to assign variations
    attr_reader :attributes

    # @return [Hash] Feature definitions (usually pulled from an API or cache)
    attr_reader :features

    # @return [Hash] Force specific experiments to always assign a specific variation (used for QA)
    attr_reader :forced_variations

    # @return [Hash[String, Growthbook::InlineExperimentResult]] Tracked impressions
    attr_reader :impressions

    # @return [Hash[String, Any]] Forced feature values
    attr_reader :forced_features

    def initialize(options = {})
      @features = {}
      @forced_variations = {}
      @forced_features = {}
      @attributes = {}
      @enabled = true
      @impressions = {}

      options.transform_keys(&:to_sym).each do |key, value|
        case key
        when :enabled
          @enabled = value
        when :attributes
          self.attributes = value
        when :url
          @url = value
        when :decryption_key
          nil
        when :encrypted_features
          decrypted = decrypted_features_from_options(options)
          self.features = decrypted unless decrypted.nil?
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
      return get_feature_result(@forced_features[key.to_s], 'override', nil, nil) if @forced_features.key?(key.to_s)

      # Return if we can't find the feature definition
      feature = get_feature(key)
      return get_feature_result(nil, 'unknownFeature', nil, nil) unless feature

      feature.rules.each do |rule|
        # Targeting condition
        next if rule.condition && !condition_passes?(rule.condition)

        # If there are filters for who is included (e.g. namespaces)
        next if rule.filters && filtered_out?(rule.filters || [])

        # If this is a percentage rollout, skip if not included
        if rule.force?
          seed = rule.seed || key
          hash_attribute = rule.hash_attribute || 'id'
          included_in_rollout = included_in_rollout?(
            seed: seed.to_s,
            hash_attribute: hash_attribute,
            range: rule.range,
            coverage: rule.coverage,
            hash_version: rule.hash_version
          )
          next unless included_in_rollout

          return get_feature_result(rule.force, 'force', nil, nil)
        end
        # Experiment rule
        next unless rule.experiment?

        exp = rule.to_experiment(key)
        next if exp.nil?

        result = _run(exp, key)

        next unless result.in_experiment && !result.passthrough

        return get_feature_result(result.value, 'experiment', exp, result)
      end

      # Fallback
      get_feature_result(feature.default_value || nil, 'defaultValue', nil, nil)
    end

    def run(exp)
      _run(exp)
    end

    def on?(key)
      eval_feature(key).on
    end

    def off?(key)
      eval_feature(key).off
    end

    def feature_value(key, fallback = nil)
      value = eval_feature(key).value
      value.nil? ? fallback : value
    end

    private

    def _run(exp, feature_id = '')
      key = exp.key

      # 1. If experiment doesn't have enough variations, return immediately
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if exp.variations.length < 2

      # 2. If context is disabled, return immediately
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) unless @enabled

      # 3. If forced via URL querystring
      override_url = @url
      unless override_url.nil?
        qs_override = Util.get_query_string_override(key, override_url, exp.variations.length)
        return get_experiment_result(exp, qs_override, hash_used: false, feature_id: feature_id) unless qs_override.nil?
      end

      # 4. If variation is forced in the context, return the forced value
      if @forced_variations.key?(key.to_s)
        return get_experiment_result(
          exp,
          @forced_variations[key.to_s],
          hash_used: false,
          feature_id: feature_id
        )
      end

      # 5. Exclude if not active
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) unless exp.active

      # 6. Get hash_attribute/value and return if empty
      hash_attribute = exp.hash_attribute || 'id'
      hash_value = get_attribute(hash_attribute).to_s
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if hash_value.empty?

      # 7. Exclude if user is filtered out (used to be called "namespace")
      if exp.filters
        return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if filtered_out?(exp.filters || [])
      elsif exp.namespace && !Growthbook::Util.in_namespace?(hash_value, exp.namespace)
        return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id)
      end

      # 8. Exclude if condition is false
      if exp.condition && !condition_passes?(exp.condition)
        return get_experiment_result(
          exp,
          -1,
          hash_used: false,
          feature_id: feature_id
        )
      end

      # 9. Get bucket ranges and choose variation
      ranges = exp.ranges || Growthbook::Util.get_bucket_ranges(
        exp.variations.length,
        exp.coverage,
        exp.weights
      )
      seed = exp.seed || key || ''
      n = Growthbook::Util.get_hash(seed: seed, value: hash_value, version: exp.hash_version || 1)
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if n.nil?

      assigned = Growthbook::Util.choose_variation(n, ranges)

      # 10. Return if not in experiment
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if assigned.negative?

      # 11. Experiment has a forced variation
      return get_experiment_result(exp, exp.force, hash_used: false, feature_id: feature_id) unless exp.force.nil?

      # 12. Exclude if in QA mode
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if @qa_mode

      # 13. Build the result object
      result = get_experiment_result(exp, assigned, hash_used: true, feature_id: feature_id, bucket: n)

      # 14. Fire tracking callback
      track_experiment(exp, result)

      # 15. Return the result
      result
    end

    def stringify_keys(hash)
      new_hash = {}
      hash.each do |key, value|
        new_hash[key.to_s] = value
      end
      new_hash
    end

    def condition_passes?(condition)
      return false if condition.nil?

      Growthbook::Conditions.eval_condition(@attributes, condition)
    end

    def get_experiment_result(experiment, variation_index = -1, hash_used: false, feature_id: '', bucket: nil)
      in_experiment = true
      if variation_index.negative? || variation_index >= experiment.variations.length
        variation_index = 0
        in_experiment = false
      end

      hash_attribute = experiment.hash_attribute || 'id'
      hash_value = get_attribute(hash_attribute)
      meta = experiment.meta ? experiment.meta[variation_index] : {}

      result = Growthbook::InlineExperimentResult.new(
        {
          key: meta['key'] || variation_index,
          in_experiment: in_experiment,
          variation_id: variation_index,
          value: experiment.variations[variation_index],
          hash_used: hash_used,
          hash_attribute: hash_attribute,
          hash_value: hash_value,
          feature_id: feature_id,
          bucket: bucket,
          name: meta['name']
        }
      )

      result.passthrough = true if meta['passthrough']

      result
    end

    def get_feature_result(value, source, experiment, experiment_result)
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
      return if listener.nil?

      @listener.on_experiment_viewed(experiment, result) if @listener.respond_to?(:on_experiment_viewed)
      @impressions[experiment.key] = result unless experiment.key.nil?
    end

    def included_in_rollout?(seed:, hash_attribute:, hash_version:, range:, coverage:)
      return true if range.nil? && coverage.nil?

      hash_value = get_attribute(hash_attribute)

      return false if hash_value.empty?

      n = Growthbook::Util.get_hash(seed: seed, value: hash_value, version: hash_version || 1)
      return false if n.nil?

      return Growthbook::Util.in_range?(n, range) if range
      return n <= coverage if coverage

      true
    end

    def filtered_out?(filters)
      filters.any? do |filter|
        hash_value = get_attribute(filter['attribute'] || 'id')

        if hash_value.empty?
          false
        else
          n = Growthbook::Util.get_hash(seed: filter['seed'] || '', value: hash_value, version: filter['hashVersion'] || 2)

          return true if n.nil?

          filter['ranges'].none? { |range| Growthbook::Util.in_range?(n, range) }
        end
      end
    end

    def decrypted_features_from_options(options)
      decrypted_features = DecryptionUtil.decrypt(options[:encrypted_features], key: options[:decryption_key])

      return nil if decrypted_features.nil?

      JSON.parse(decrypted_features)
    rescue StandardError
      nil
    end
  end
end
