# frozen_string_literal: true

module Growthbook
  # internal use only
  # Remote saved groups (growthbook/growthbook#7277). A remote saved group keeps
  # its members outside the payload, which only says which attribute the group is
  # about: `{ "type" => "remote", "attributeKey" => ... }`. The app resolves which
  # of them a user is in, and conditions read the ids from the reserved
  # `__gb_remoteGroupIds` attribute.
  module RemoteSavedGroups
    # The attribute conditions read a user's remote saved groups from. Internal
    # attributes start with `__gb_`, matching GrowthBook's back end.
    ATTRIBUTE = '__gb_remoteGroupIds'

    NO_GROUPS = [].freeze

    # Evaluation checks for remote groups often, so each payload is scanned once.
    # One entry is enough: a context holds one saved groups hash at a time.
    @last_scan = nil

    # Warned once per process, since apps usually make a context per request
    @warned_missing_ids = false

    # The payload's remote saved groups, as a resolver gets them: hashes with
    # 'id', 'attributeKey' and, for a derived group, 'valuesFrom'. Only v2
    # payloads carry this metadata.
    def self.groups(saved_groups)
      return NO_GROUPS if saved_groups.nil? || saved_groups.empty?

      last = @last_scan
      return last[1] if last && last[0].equal?(saved_groups)

      groups = saved_groups.each_with_object([]) do |(id, entry), found|
        # A remote entry without an attribute gives a resolver nothing to look up,
        # so its rules fail closed
        next unless entry.is_a?(Hash) && entry['type'] == 'remote' && entry['attributeKey'].is_a?(String)

        group = { 'id' => id.to_s, 'attributeKey' => entry['attributeKey'] }
        group['valuesFrom'] = entry['valuesFrom'] if entry['valuesFrom']
        found << group.freeze
      end.freeze
      @last_scan = [saved_groups, groups]
      groups
    end

    # Asks resolver which of the payload's remote groups the user is in. Only the
    # attributes those groups use are passed. Raises what the resolver raises.
    #
    # Returns [] when the payload lists no remote groups. Don't set that as the
    # user's remote group ids: the payload may still check `__gb_remoteGroupIds`
    # directly, and [] makes "not in group" rules match. Check groups first.
    def self.resolve(attributes, saved_groups, resolver)
      groups = groups(saved_groups)
      return [] if groups.empty?

      used = groups.each_with_object({}) do |group, out|
        # Keyed by attributeKey, which can be a dot-separated path
        value = Growthbook::Conditions.get_path(attributes, group['attributeKey'])
        out[group['attributeKey']] = value unless value.nil?
      end
      ids = resolver.call(used, groups)
      raise TypeError, 'a saved group resolver must return an array of group ids' unless ids.is_a?(Array)

      ids.map(&:to_s)
    end

    # Whether the payload has remote groups but the user has no remote group ids,
    # so every rule using them will fail
    def self.missing_ids?(attributes, remote_group_ids, saved_groups)
      remote_group_ids.nil? && !attributes[ATTRIBUTE].is_a?(Array) && !groups(saved_groups).empty?
    end

    # Logs once when the user has no remote group ids for the payload's remote
    # groups. Logs no attribute values.
    def self.warn_if_missing_ids(attributes, remote_group_ids, saved_groups)
      return if @warned_missing_ids || !missing_ids?(attributes, remote_group_ids, saved_groups)

      @warned_missing_ids = true
      warn(
        'GrowthBook: the payload has remote saved groups, but the user has no remote group ids. ' \
        "Rules using them won't match. See Context#add_remote_saved_groups."
      )
    end

    # The attributes conditions see: attributes, with the resolved remote group
    # ids (when set) as `__gb_remoteGroupIds`, over any value the attributes set
    # for it. A copy, so the caller's hash is left as it was.
    def self.with_ids(attributes, remote_group_ids)
      return attributes if remote_group_ids.nil?

      attributes.merge(ATTRIBUTE => remote_group_ids)
    end
  end
end
