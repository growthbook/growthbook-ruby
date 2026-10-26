# frozen_string_literal: true

module Growthbook
  # internal use only
  # Shrinks a features payload for a user whose attributes are only partly known,
  # e.g. on a server bootstrapping a client SDK. The result evaluates the same as
  # the full payload for anyone who agrees with the known attributes.
  class PayloadReducer
    # @param payload [Hash] A decrypted features payload, as returned by the SDK API
    # @param attributes [Hash] The attributes known for the user
    # @param include [Hash] Keep only what matches every filter: projects, tags, customFields
    # @param exclude [Hash] Drop what matches any filter: projects, tags, customFields
    # @param prerequisites ['keep', 'filter'] With 'keep', prerequisites of kept features
    #   and experiments are kept even when the filters drop them
    def initialize(payload, attributes:, include:, exclude:, prerequisites:)
      @payload = payload
      @attributes = attributes
      @include = include
      @exclude = exclude
      @filter_prerequisites = prerequisites.to_s == 'filter'
      @saved_groups = payload['savedGroups'] || {}
      @all_features = payload['features'] || {}
      @added = {}
    end

    def reduce
      @all_features.each do |id, feature|
        add(id) if matches?(feature.is_a?(Hash) ? feature['metadata'] : nil)
      end
      experiments = (@payload['experiments'] || []).select { |e| matches?(e['metadata']) }.map { |e| prune(e) }
      experiments.each { |e| add_parents(e) }

      reduced = @payload.merge('features' => @added, 'experiments' => experiments)
      # Only when there were any, as with the payload's other optional keys
      reduced['contextualBandits'] = contextual_bandits(experiments) unless @payload['contextualBandits'].nil?
      reduced['savedGroups'] = used_saved_groups([@added, experiments, reduced['contextualBandits']])
      reduced
    end

    private

    # Only an array counts, as with `$in`, and any one of its values is enough
    def has?(actual, want)
      want.is_a?(Array) && Growthbook::Conditions.in?(actual, want)
    end

    # A rule without projects applies wherever its feature is delivered
    def rule_in_projects?(meta)
      @include['projects'].nil? || meta.nil? || meta['projects'].nil? || has?(meta['projects'], @include['projects'])
    end

    # A feature or experiment has to list one of the projects, or be in all of
    # them. One without projects is in none, like one without tags.
    def in_projects?(meta)
      @include['projects'].nil? || meta['allProjects'] || has?(meta['projects'], @include['projects'])
    end

    # Kept when it matches every `include` filter and no `exclude` filter. Only
    # listed projects are excluded, so one in all projects stays.
    def matches?(meta)
      meta ||= {}
      fields = meta['customFields'] || {}
      in_fields = @include['customFields'] || {}
      out_fields = @exclude['customFields'] || {}
      in_projects?(meta) &&
        (@include['tags'].nil? || has?(meta['tags'], @include['tags'])) &&
        in_fields.all? { |k, want| has?(fields[k], want) } &&
        !has?(meta['projects'], @exclude['projects']) &&
        !has?(meta['tags'], @exclude['tags']) &&
        out_fields.none? { |k, want| has?(fields[k], want) }
    end

    # Reduces a rule or an auto experiment
    def prune(item)
      condition = item['condition'] ? Growthbook::Conditions.prune_condition(@attributes, item['condition'], @saved_groups) : nil
      item = item.dup
      if condition == true
        item.delete('condition')
      elsif condition == false
        # Kept, since sticky buckets and forced variations skip an experiment's
        # condition, and a rule's prerequisites are checked before it
        item['condition'] = { '$not' => {} }
        # A force rule that never passes never returns its value
        item['force'] = nil if item.key?('force')
      elsif condition
        item['condition'] = condition
      end
      item
    end

    # Adds the prerequisites the client evaluates for a rule or experiment, even
    # when the filters drop them. With 'filter', only the filters decide, except
    # for holdouts, which aren't app features and are always kept.
    def add_parents(item)
      (item['parentConditions'] || []).each do |parent|
        id = parent['id']
        add(id) if !@filter_prerequisites || id.to_s.start_with?('$holdout:')
      end
    end

    def add(id)
      feature = @all_features[id]
      return if !feature.is_a?(Hash) || @added.key?(id)

      # Rules scoped to other projects aren't served. A prerequisite from another
      # project keeps its own, as on the server.
      scoped = in_projects?(feature['metadata'] || {})
      rules = feature['rules']&.select { |r| !scoped || rule_in_projects?(r['metadata']) }&.map { |r| prune(r) }
      # Stored before its parents are added, so a prerequisite cycle ends
      @added[id] = rules ? feature.merge('rules' => rules) : feature
      (rules || []).each { |r| add_parents(r) }
    end

    # The contextual bandits that kept rules and experiments use. A context whose
    # condition never passes can't be the first that does, so it goes.
    def contextual_bandits(experiments)
      all_bandits = @payload['contextualBandits'] || {}
      bandits = {}
      (@added.values.flat_map { |f| f['rules'] || [] } + experiments).each do |item|
        ref = item['contextualBanditRef']
        next if !ref || bandits.key?(ref) || !all_bandits.key?(ref)

        bandit = all_bandits[ref]
        contexts = (bandit['contexts'] || []).flat_map do |c|
          condition = Growthbook::Conditions.prune_condition(@attributes, c['condition'] || {}, @saved_groups)
          next [] if condition == false

          [c.merge('condition' => condition == true ? {} : condition)]
        end
        bandits[ref] = bandit.merge('contexts' => contexts)
      end
      bandits
    end

    # Each saved group whose id appears as a string anywhere in `value`, with
    # condition groups reduced. This needs no list of the operators that
    # reference groups.
    def used_saved_groups(value, groups = {})
      case value
      when String
        return groups if !@saved_groups.key?(value) || groups.key?(value)

        condition = Growthbook::Conditions.prune_saved_group(@attributes, { 'id' => value }, @saved_groups)
        groups[value] = condition.is_a?(Hash) ? @saved_groups[value].merge('condition' => condition) : @saved_groups[value]
        used_saved_groups(groups[value], groups)
      when Hash
        value.each_value { |v| used_saved_groups(v, groups) }
      when Array
        value.each { |v| used_saved_groups(v, groups) }
      end
      groups
    end
  end
end
