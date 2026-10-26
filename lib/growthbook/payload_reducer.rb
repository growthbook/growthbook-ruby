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
      @as_written = {}
      @on_cycle = nil
    end

    def reduce
      @all_features.each do |id, feature|
        add(id) if matches?(feature.is_a?(Hash) ? feature['metadata'] : nil)
      end
      experiments = (@payload['experiments'] || []).select { |e| matches?(e['metadata']) }.map { |e| prune(e, false) }
      experiments.each { |e| add_parents(e) }

      reduced = @payload.merge('features' => @added, 'experiments' => experiments)
      # Only when there were any, as with the payload's other optional keys
      reduced['contextualBandits'] = contextual_bandits(experiments) unless @payload['contextualBandits'].nil?
      used = [@added, experiments, reduced['contextualBandits']]
      mark_as_written(used, true, {})
      reduced['savedGroups'] = used_saved_groups(used)
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
    def prune(item, rule)
      condition = item['condition'] ? Growthbook::Conditions.prune_condition(@attributes, item['condition'], @saved_groups) : nil
      item = item.dup
      if condition == true
        item.delete('condition')
      elsif condition == false
        # Kept, since sticky buckets and forced variations skip an experiment's
        # condition, and a rule's prerequisites are checked before it
        item['condition'] = { '$not' => {} }
        # A force rule that never passes never returns its value. An auto
        # experiment's forced variation still applies to a sticky bucketed user.
        item['force'] = nil if rule && item.key?('force')
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
      rules = feature['rules']&.select { |r| !scoped || rule_in_projects?(r['metadata']) }&.map { |r| prune(r, true) }
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
        # Evaluation tolerates a definition that isn't a Hash, so it stays
        unless bandit.is_a?(Hash)
          bandits[ref] = bandit
          next
        end

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

        # Groups evaluated against something other than the user, or on a
        # cycle, keep their condition as written
        reducible = !@as_written.key?(value) && !on_cycle.key?(value)
        condition = reducible ? Growthbook::Conditions.prune_saved_group(@attributes, { 'id' => value }, @saved_groups) : nil
        groups[value] = condition.is_a?(Hash) ? @saved_groups[value].merge('condition' => condition) : @saved_groups[value]
        used_saved_groups(groups[value], groups)
      when Hash
        value.each_value { |v| used_saved_groups(v, groups) }
      when Array
        value.each { |v| used_saved_groups(v, groups) }
      end
      groups
    end

    # Marks the groups that keep their condition as written: those evaluated
    # against something other than the user (each item in $elemMatch, or the
    # parent's value in a prerequisite), and the groups those reference
    def mark_as_written(value, user, seen)
      case value
      when String
        return if !@saved_groups.key?(value) || @as_written.key?(value)
        return if user && seen.key?(value)

        (user ? seen : @as_written)[value] = true
        mark_as_written(@saved_groups[value], user, seen)
      when Hash
        value.each { |k, v| mark_as_written(v, user && k != '$elemMatch' && k != 'parentConditions', seen) }
      when Array
        value.each { |v| mark_as_written(v, user, seen) }
      end
    end

    # A group on a cycle can't be reduced on its own: its result depends on
    # which group the evaluation entered the cycle from. The groups on a cycle
    # are found once, as strongly connected components with more than one
    # group or a group that references itself.
    def on_cycle
      @on_cycle ||= groups_on_cycles
    end

    # Iterative Tarjan's algorithm over the group reference graph, so each
    # group's entry is scanned once however many groups share it
    def groups_on_cycles
      edges = {}
      @saved_groups.each_key { |id| edges[id] = group_ids(@saved_groups[id]).uniq }

      index = {}
      low = {}
      on_stack = {}
      stack = []
      result = {}
      counter = 0
      edges.each_key do |root|
        next if index.key?(root)

        work = [[root, 0]]
        index[root] = low[root] = counter
        counter += 1
        stack << root
        on_stack[root] = true
        until work.empty?
          node, i = work.last
          children = edges[node]
          if i < children.length
            work.last[1] = i + 1
            child = children[i]
            if !index.key?(child)
              index[child] = low[child] = counter
              counter += 1
              stack << child
              on_stack[child] = true
              work << [child, 0]
            elsif on_stack[child]
              low[node] = [low[node], index[child]].min
            end
            next
          end

          work.pop
          low[work.last[0]] = [low[work.last[0]], low[node]].min unless work.empty?
          next unless low[node] == index[node]

          component = []
          loop do
            member = stack.pop
            on_stack.delete(member)
            component << member
            break if member == node
          end
          next unless component.length > 1 || children.include?(node)

          component.each { |member| result[member] = true }
        end
      end
      result
    end

    def group_ids(value, found = [])
      case value
      when String
        found << value if @saved_groups.key?(value)
      when Hash
        value.each_value { |v| group_ids(v, found) }
      when Array
        value.each { |v| group_ids(v, found) }
      end
      found
    end
  end
end
