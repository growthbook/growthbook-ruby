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

    # @return [Growthbook::FeatureUsageCallback] An object that responds to `on_feature_usage(String, Growthbook::FeatureResult)`
    attr_accessor :on_feature_usage

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

    # @return [Growthbook::StickyBucketService] Sticky bucket service for sticky bucketing
    attr_reader :sticky_bucket_service

    # @return [String] The attributes that identify users. If omitted, this will be inferred from the feature definitions
    attr_reader :sticky_bucket_identifier_attributes

    # @return [String] The attributes that are used to assign sticky buckets
    attr_reader :sticky_bucket_assignment_docs

    # @return [Boolean] If true, the context is using derived sticky bucket attributes
    attr_reader :using_derived_sticky_bucket_attributes
    
    # @return [Hash[String, String]] The attributes that are used to assign sticky buckets
    attr_reader :sticky_bucket_attributes

    def initialize(options = {})
      @features = {}
      @attributes = {}
      @forced_variations = {}
      @forced_features = {}
      @attributes = {}
      @enabled = true
      @impressions = {}
      @sticky_bucket_assignment_docs = {}

      features = {}
      attributes = {}

      options.transform_keys(&:to_sym).each do |key, value|
        case key
        when :enabled
          @enabled = value
        when :attributes
          attributes = value
        when :url
          @url = value
        when :decryption_key
          nil
        when :encrypted_features
          decrypted = decrypted_features_from_options(options)
          features = decrypted unless decrypted.nil?
        when :features
          features = value
        when :forced_variations, :forcedVariations
          self.forced_variations = value
        when :forced_features
          self.forced_features = value
        when :qa_mode, :qaMode
          @qa_mode = value
        when :listener
          @listener = value
        when :on_feature_usage
          @on_feature_usage = value
        when :sticky_bucket_service
          @sticky_bucket_service = value
        when :sticky_bucket_identifier_attributes
          @sticky_bucket_identifier_attributes = value
        else
          warn("Unknown context option: #{key}")
        end
      end

      @using_derived_sticky_bucket_attributes = !@sticky_bucket_identifier_attributes
      self.attributes = attributes
      self.features = features
    end

    def features=(features)
      @features = {}

      return if features.nil?

      features.each do |k, v|
        # Convert to a Feature object if it's not already
        v = Growthbook::Feature.new(v) unless v.is_a? Growthbook::Feature

        @features[k.to_s] = v
      end

      refresh_sticky_buckets
    end

    def attributes=(attrs)
      @attributes = stringify_keys(attrs || {})

      refresh_sticky_buckets
    end

    def forced_variations=(forced_variations)
      @forced_variations = stringify_keys(forced_variations || {})
    end

    def forced_features=(forced_features)
      @forced_features = stringify_keys(forced_features || {})
    end

    def eval_feature(key)
      _eval_feature(key, Set.new)
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

    def _eval_prereqs(parent_conditions, stack)
      parent_conditions.each do |parent_condition|
        parent_res = _eval_feature(parent_condition["id"], stack)

        return "cyclic" if parent_res.source == "cyclicPrerequisite"

        unless evalCondition({ "value" => parent_res.value }, parent_condition["condition"])
          return "gate" if parent_condition["gate"]
          return "fail"
        end
      end
      "pass"
    end

    def _eval_feature(key, stack)
      # Forced in the context
      return get_feature_result(key.to_s, @forced_features[key.to_s], 'override', nil, nil) if @forced_features.key?(key.to_s)

      # Return if we can't find the feature definition
      feature = get_feature(key)
      return get_feature_result(key.to_s, nil, 'unknownFeature', nil, nil) unless feature

      return get_feature_result(key.to_s, nil, "cyclicPrerequisite", nil, nil) if stack.include?(key)
      stack.add(key)

      feature.rules.each do |rule|
        if rule.parent_conditions && rule.parent_conditions.length > 0
          prereq_res = _eval_prereqs(rule.parent_conditions, stack)
          case prereq_res
          when "gate"
            return get_feature_result(key.to_s, nil, "prerequisite", nil, nil)
          when "cyclic"
            # Warning already logged in this case
            return get_feature_result(key.to_s, nil, "cyclicPrerequisite", nil, nil)
          when "fail"
            next
          end
        end

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
            fallback_attribute: rule.fallback_attribute,
            range: rule.range,
            coverage: rule.coverage,
            hash_version: rule.hash_version
          )
          next unless included_in_rollout

          return get_feature_result(key.to_s, rule.force, 'force', nil, nil)
        end
        # Experiment rule
        next unless rule.experiment?

        exp = rule.to_experiment(key)
        next if exp.nil?

        result = _run(exp, key)

        next unless result.in_experiment && !result.passthrough

        return get_feature_result(key.to_s, result.value, 'experiment', exp, result)
      end

      # Fallback
      get_feature_result(key.to_s, feature.default_value.nil? ? nil : feature.default_value, 'defaultValue', nil, nil)
    end

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
      hash_attribute, hash_value_raw = get_hash_attribute(exp.hash_attribute, exp.fallback_attribute)
      hash_value = hash_value_raw.to_s
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if hash_value.empty?

      assigned = -1

      found_sticky_bucket = false
      sticky_bucket_version_is_blocked = false
      if sticky_bucket_service && !experiment.disable_sticky_bucketing
        sticky_bucket = _get_sticky_bucket_variation(
          experiment.key,
          experiment.bucket_version,
          experiment.min_bucket_version,
          experiment.meta,
          hash_attribute: experiment.hash_attribute,
          fallback_attribute: experiment.fallback_attribute
        )
        found_sticky_bucket = sticky_bucket['variation'].to_i >= 0
        assigned = sticky_bucket['variation'].to_i
        sticky_bucket_version_is_blocked = sticky_bucket['versionIsBlocked']
      end

      # Some checks are not needed if we already have a sticky bucket
      if !found_sticky_bucket
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

        # 8.01 Exclude if parent conditions are not met
        if exp.parent_conditions
          prereq_res = _eval_prereqs(exp.parent_conditions, Set.new)
          if ["gate", "fail", "cyclic"].include?(prereq_res)
            return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id)
          end
        end
      end

      # 9. Get bucket ranges and choose variation
      seed = exp.seed || key || ''
      n = Growthbook::Util.get_hash(seed: seed, value: hash_value, version: exp.hash_version || 1)
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if n.nil?

      if !found_sticky_bucket
        ranges = exp.ranges || Growthbook::Util.get_bucket_ranges(
          exp.variations.length,
          exp.coverage,
          exp.weights
        )
        assigned = Growthbook::Util.choose_variation(n, ranges)
      end

      # Unenroll if any prior sticky buckets are blocked by version
      return get_experiment_result(exp, -1, hash_used: false, feature_id: featureId, sticky_bucket_used: true) if sticky_bucket_version_is_blocked

      # 10. Return if not in experiment
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if assigned.negative?

      # 11. Experiment has a forced variation
      return get_experiment_result(exp, exp.force, hash_used: false, feature_id: feature_id) unless exp.force.nil?

      # 12. Exclude if in QA mode
      return get_experiment_result(exp, -1, hash_used: false, feature_id: feature_id) if @qa_mode

      # 13. Build the result object
      result = get_experiment_result(exp, assigned, hash_used: true, feature_id: feature_id, bucket: n, sticky_bucket_used: found_sticky_bucket)


      # 13.5 Persist sticky bucket
      if sticky_bucket_service && !experiment.disable_sticky_bucketing
        assignment = {
          _get_sticky_bucket_experiment_key(experiment.key, experiment.bucket_version) => result.key
        }

        data = _generate_sticky_bucket_assignment_doc(hash_attribute, hash_value, assignment)
        doc = data['doc']
        if doc && data['changed']
          @sticky_bucket_assignment_docs ||= {}
          @sticky_bucket_assignment_docs[data['key']] = doc
          sticky_bucket_service.save_assignments(doc)
        end
      end

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

    def get_experiment_result(experiment, variation_index = -1, hash_used: false, feature_id: '', bucket: nil, sticky_bucket_used: false)
      in_experiment = true
      if variation_index.negative? || variation_index >= experiment.variations.length
        variation_index = 0
        in_experiment = false
      end

      hash_attribute, hash_value = get_hash_attribute(experiment.hash_attribute, experiment.fallback_attribute)
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
          name: meta['name'],
          sticky_bucket_used: sticky_bucket_used
        }
      )

      result.passthrough = true if meta['passthrough']

      result
    end

    def get_feature_result(key, value, source, experiment, experiment_result)
      res = Growthbook::FeatureResult.new(value, source, experiment, experiment_result)

      track_feature_usage(key, res)

      res
    end

    def track_feature_usage(key, feature_result)
      return unless on_feature_usage.respond_to?(:on_feature_usage)
      return if feature_result.source == 'override'

      on_feature_usage.on_feature_usage(key, feature_result)
    end

    def get_feature(key)
      return @features[key.to_sym] if @features.key?(key.to_sym)
      return @features[key.to_s] if @features.key?(key.to_s)

      nil
    end

    def get_hash_attribute(attr, fallback_attr)
      attr = attr || "id"

      val = get_attribute(attr)

      # If no match, try fallback
      if val.nil? || val == "" && fallback_attr && @sticky_bucket_service
        val = get_attribute(fallback_attr)
        attr = fallback_attr unless val.nil? || val == ""
      end

      [attr, val]
    end

    def get_attribute(key)
      return '' if key.nil?

      return @attributes[key.to_sym] if @attributes.key?(key.to_sym)
      return @attributes[key.to_s] if @attributes.key?(key.to_s)

      ''
    end

    def track_experiment(experiment, result)
      return if listener.nil?

      @listener.on_experiment_viewed(experiment, result) if @listener.respond_to?(:on_experiment_viewed)
      @impressions[experiment.key] = result unless experiment.key.nil?
    end

    def included_in_rollout?(seed:, hash_attribute:, fallback_attribute:, hash_version:, range:, coverage:)
      return true if range.nil? && coverage.nil?

      _, hash_value_raw = get_hash_attribute(hash_attribute, fallback_attribute)

      hash_value = hash_value_raw.to_s

      return false if hash_value.empty?

      n = Growthbook::Util.get_hash(seed: seed, value: hash_value, version: hash_version || 1)
      return false if n.nil?

      return Growthbook::Util.in_range?(n, range) if range
      return n <= coverage if coverage

      true
    end

    def filtered_out?(filters)
      filters.any? do |filter|
        hash_value = get_attribute(filter['attribute'] || 'id').to_s

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

    def _derive_sticky_bucket_identifier_attributes
      attributes = Set.new
      @features.each do |key, feature|
        feature.rules.each do |rule|
          if rule.variations
            attributes.add(rule.hashAttribute || "id")
            attributes.add(rule.fallbackAttribute) if rule.fallbackAttribute
          end
        end
      end
      attributes.to_a
    end

    def _get_sticky_bucket_attributes
      attributes = {}
      if @using_derived_sticky_bucket_attributes
        @sticky_bucket_identifier_attributes = _derive_sticky_bucket_identifier_attributes
      end

      return attributes unless @sticky_bucket_identifier_attributes

      @sticky_bucket_identifier_attributes.each do |attr|
        _, hash_value = _getHashValue(attr)
        attributes[attr] = hash_value if hash_value
      end
      attributes
    end

    def _get_sticky_bucket_assignments(attr = nil, fallback = nil)
      merged = {}

      _, hash_value = _getHashValue(attr)
      key = "#{attr}||#{hash_value}"
      if @sticky_bucket_assignment_docs.key?(key)
        merged = @sticky_bucket_assignment_docs[key]["assignments"]
      end

      if fallback
        _, hash_value = _getHashValue(fallback)
        key = "#{fallback}||#{hash_value}"
        if @sticky_bucket_assignment_docs.key?(key)
          @sticky_bucket_assignment_docs[key]["assignments"].each do |k, v|
            merged[k] = v unless merged.key?(k)
          end
        end
      end

      merged
    end

    def _is_blocked(assignments, experiment_key, min_bucket_version)
      return false if min_bucket_version.zero?

      (0...min_bucket_version).each do |i|
        blocked_key = _get_sticky_bucket_experiment_key(experiment_key, i)
        return true if assignments.key?(blocked_key)
      end
      false
    end

    def _get_sticky_bucket_variation(experiment_key, bucket_version = nil, min_bucket_version = nil, meta = nil, hash_attribute = nil, fallback_attribute = nil)
      bucket_version ||= 0
      min_bucket_version ||= 0
      meta ||= []

      id = _get_sticky_bucket_experiment_key(experiment_key, bucket_version)

      assignments = _get_sticky_bucket_assignments(hash_attribute, fallback_attribute)
      if _is_blocked(assignments, experiment_key, min_bucket_version)
        return {
          'variation' => -1,
          'versionIsBlocked' => true
        }
      end

      variation_key = assignments[id]
      return { 'variation' => -1 } unless variation_key

      variation = meta.find_index { |v| v["key"] == variation_key } || -1
      return { 'variation' => -1 } if variation < 0

      { 'variation' => variation }
    end

    def _get_sticky_bucket_experiment_key(experiment_key, bucket_version = 0)
      "#{experiment_key}__#{bucket_version}"
    end

    def refresh_sticky_buckets(force = false)
      return unless @sticky_bucket_service

      attributes = _get_sticky_bucket_attributes
      if !force && attributes == @sticky_bucket_attributes
        logger.debug("Skipping refresh of sticky bucket assignments, no changes")
        return
      end

      @sticky_bucket_attributes = attributes
      @sticky_bucket_assignment_docs = @sticky_bucket_service.get_all_assignments(attributes)
    end

    def _generate_sticky_bucket_assignment_doc(attribute_name, attribute_value, assignments)
      key = "#{attribute_name}||#{attribute_value}"
      existing_assignments = @sticky_bucket_assignment_docs[key]&.fetch("assignments", {})

      new_assignments = existing_assignments.merge(assignments)

      existing_json = JSON.dump(existing_assignments, sort_keys: true)
      new_json = JSON.dump(new_assignments, sort_keys: true)
      changed = existing_json != new_json

      {
        'key' => key,
        'doc' => {
          'attributeName' => attribute_name,
          'attributeValue' => attribute_value,
          'assignments' => new_assignments
        },
        'changed' => changed
      }
    end
  end
end
