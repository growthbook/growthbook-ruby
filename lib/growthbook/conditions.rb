# frozen_string_literal: true

require 'json'
require 'set'

module Growthbook
  # internal use only
  # Utils for condition evaluation
  class Conditions # rubocop:disable Metrics/ClassLength
    # Keys a condition can have that aren't attributes, besides $not, which is
    # also an operator on a value
    CONDITION_OPERATORS = %w[$or $nor $and $savedGroup].freeze

    # Keys that pass when what they hold fails
    NEGATING_KEYS = %w[$not $nor].freeze

    # Saved groups for one evaluation, and the group ids already being resolved, to stop cycles
    class EvalContext
      # @return [Hash] Saved groups payload, keyed by group id
      attr_reader :saved_groups

      # @return [Set<String>] Ids of the saved groups being resolved
      attr_reader :visited

      def initialize(saved_groups, visited = Set.new)
        @saved_groups = saved_groups || {}
        @visited = visited
      end

      # A copy that also holds id, so sibling groups don't see each other's ids
      def visiting(id)
        EvalContext.new(@saved_groups, @visited.dup.add(id))
      end
    end

    # Evaluate a targeting conditions hash against an attributes hash
    # Both attributes and conditions only have string keys (no symbols)
    def self.eval_condition(attributes, condition, saved_groups = {})
      eval_condition_result(attributes, condition, EvalContext.new(saved_groups)) == true
    end

    # Partially evaluate a condition when only some attributes are known, e.g. on
    # a server. Attributes missing from `attributes` are unknown. Returns true or
    # false once the result can't depend on them, otherwise the condition minus
    # every branch that is already decided.
    def self.prune_condition(attributes, condition, saved_groups = {})
      prune_with_context(attributes, condition, EvalContext.new(saved_groups))
    end

    # Prune the saved group a reference points to. Returns its result once decided
    # (nil for a group type this SDK doesn't know), otherwise its condition minus
    # every branch that is already decided. A malformed condition group stays as written.
    def self.prune_saved_group(attributes, reference, saved_groups)
      eval_saved_group(attributes, reference, EvalContext.new(saved_groups), prune: true, keep_malformed: true)
    end

    # Helper function to ensure conditions only have string keys (no symbols)
    def self.parse_condition(condition)
      case condition
      when Array
        return condition.map { |v| parse_condition(v) }
      when Hash
        # Not to_h with a block, which Ruby 2.5 ignores
        return condition.each_with_object({}) { |(k, v), h| h[k.to_s] = parse_condition(v) }
      end
      condition
    end

    # Evaluates a condition to true or false, or nil when the result depends on an
    # operator or saved group type this SDK doesn't support
    def self.eval_condition_result(attributes, condition, ctx)
      # @type var result: bool?
      result = true
      condition.each do |key, value|
        r = case key
            when '$or' then eval_or(attributes, value, ctx)
            when '$nor' then negate(eval_or(attributes, value, ctx))
            when '$and' then eval_and(attributes, value, ctx)
            when '$not' then negate(eval_condition_result(attributes, value, ctx))
            when '$savedGroup' then eval_saved_group(attributes, value, ctx)
            else eval_condition_value(value, get_path(attributes, key), ctx)
        end
        # One failing entry decides it, wherever an unsupported one is
        return false if r == false

        result = nil if r.nil?
      end
      result
    end

    # $not of an undecided result stays undecided
    def self.negate(result)
      result.nil? ? nil : !result
    end

    def self.eval_or(attributes, conditions, ctx)
      return true if conditions.length <= 0

      # @type var result: bool?
      result = false
      conditions.each do |condition|
        r = eval_condition_result(attributes, condition, ctx)
        return true if r == true

        result = nil if r.nil?
      end
      result
    end

    def self.eval_and(attributes, conditions, ctx)
      # @type var result: bool?
      result = true
      conditions.each do |condition|
        r = eval_condition_result(attributes, condition, ctx)
        return false if r == false

        result = nil if r.nil?
      end
      result
    end

    # Resolves a `$savedGroup` reference. Anything unrecognized matches nobody.
    # With prune, an unknown attribute leaves a list group undecided (nil), and a
    # condition group is pruned rather than evaluated. With keep_malformed, a
    # condition group that raises while pruning is returned as written.
    def self.eval_saved_group(attributes, reference, ctx, prune: false, keep_malformed: false)
      return false unless reference.is_a?(Hash)

      id = reference['id']
      attribute_key = reference['attributeKey']
      return false if !id.is_a?(String) || ctx.visited.include?(id)
      # Only an absent override falls back to the entry's attribute. Falling back
      # for any other non-string, nil included, would check a different population.
      return false if reference.key?('attributeKey') && !attribute_key.is_a?(String)

      entry = ctx.saved_groups[id]
      # Absent, or a v1 bare array
      return false unless entry.is_a?(Hash)

      case entry['type']
      when 'list'
        # The override wins over the entry's own attribute
        key = attribute_key || entry['attributeKey']
        return false unless key.is_a?(String)
        return false unless entry['values'].is_a?(Array)
        return nil if prune && !known?(attributes, key)

        in?(get_path(attributes, key), entry['values'])
      when 'condition'
        # A condition group has no single attribute, so any override is ignored
        return false unless entry['condition'].is_a?(Hash)

        group_ctx = ctx.visiting(id)
        return eval_condition_result(attributes, entry['condition'], group_ctx) unless prune

        # Inside a condition being pruned, the error reaches that condition's prune_with_context
        keep_malformed ? prune_with_context(attributes, entry['condition'], group_ctx) : prune_entries(attributes, entry['condition'], group_ctx)
      end
      # Any other type was added after this SDK was built. The client SDK may support it.
    end

    def self.prune_with_context(attributes, condition, ctx)
      prune_entries(attributes, condition, ctx)
    rescue StandardError
      # One that raises, such as a malformed one, stays as written. Evaluating it
      # fails as a whole, so no part of it can be decided.
      condition
    end

    def self.prune_entries(attributes, condition, ctx)
      out = {}
      condition.each do |key, value|
        r = case key
            when '$or', '$nor', '$and' then prune_list(attributes, value, ctx, or_list: key != '$and')
            when '$not' then prune_entries(attributes, value, ctx)
            when '$savedGroup'
              # Keep an undecided reference as is rather than inlining the group
              decided = eval_saved_group(attributes, value, ctx, prune: true)
              decided?(decided) ? decided : nil
            else
              # nil when the attribute is unknown, or the value uses an operator
              # this SDK doesn't support, which the client's SDK may
              known?(attributes, key) ? eval_condition_value(value, get_path(attributes, key), ctx) : nil
        end
        # $not and $nor pass when what they hold fails
        r = !r if NEGATING_KEYS.include?(key) && decided?(r)

        # One failing entry fails the whole condition, and a passing one is dropped
        return false if r == false

        # nil is an undecided leaf, which stays as written
        if r.nil?
          out[key] = value
        elsif r != true
          out[key] = r
        end
      end
      out.empty? ? true : out
    end

    # Prune an $or (or an $and) list. Returns the conditions still undecided, or
    # the list's result once there are none.
    def self.prune_list(attributes, conditions, ctx, or_list:)
      raise TypeError, 'expected an array of conditions' unless conditions.is_a?(Array)

      out = []
      conditions.each do |condition|
        r = prune_entries(attributes, condition, ctx)
        # One passing condition decides an $or, and one failing condition an $and
        return true if or_list && r == true
        return false if !or_list && r == false

        out << r unless decided?(r)
      end
      return out unless out.empty?

      # Every condition failed an $or, or passed an $and. Like eval_or, an empty $or passes.
      or_list ? conditions.empty? : true
    end

    # True or false, rather than nil or a pruned condition
    def self.decided?(result)
      result.is_a?(TrueClass) || result.is_a?(FalseClass)
    end

    # A nested path is unknown, since the server may only have part of the object
    def self.known?(attributes, path)
      !path.include?('.') && attributes.is_a?(Hash) && attributes.key?(path)
    end

    def self.operator_object?(obj)
      obj.each do |key, _value|
        return false if key[0] != '$'
      end
      true
    end

    def self.get_type(attribute_value)
      return 'string' if attribute_value.is_a? String
      return 'number' if attribute_value.is_a? Integer
      return 'number' if attribute_value.is_a? Float
      return 'boolean' if [true, false].include?(attribute_value)
      return 'array' if attribute_value.is_a? Array
      return 'null' if attribute_value.nil?

      'object'
    end

    def self.get_path(attributes, path)
      path = path.to_s if path.is_a?(Symbol)

      parts = path.split('.')
      current = attributes

      parts.each do |value|
        return nil unless current.is_a?(Hash) && current&.key?(value)

        current = current[value]
      end

      current
    end

    def self.eval_condition_value(condition_value, attribute_value, ctx, insensitive: false)
      if condition_value.is_a?(Hash) && operator_object?(condition_value)
        # @type var result: bool?
        result = true
        condition_value.each do |key, value|
          r = eval_operator_condition(key, attribute_value, value, ctx)
          return false if r == false

          result = nil if r.nil?
        end
        return result
      end
      return condition_value.casecmp?(attribute_value) if insensitive && condition_value.is_a?(String) && attribute_value.is_a?(String)

      # Numbers compare by value, like JS ===, so 1.0 equals 1
      return number?(attribute_value) && condition_value == attribute_value if number?(condition_value)

      js_json(condition_value) == js_json(attribute_value)
    end

    # Serializes like JavaScript's JSON.stringify, which writes 1.0 as "1" and -0.0 as "0"
    def self.js_json(value)
      case value
      when Hash then "{#{value.map { |k, v| "#{k.to_s.to_json}:#{js_json(v)}" }.join(',')}}"
      when Array then "[#{value.map { |v| js_json(v) }.join(',')}]"
      when Integer, Float then value.to_f.finite? ? Util.js_number_to_s(value) : 'null'
      else value.to_json
      end
    end

    def self.elem_match(condition, attribute_value, ctx)
      return false unless attribute_value.is_a? Array

      # Operators test each element itself. A condition, including one that only
      # uses $or, $and, $nor, or $savedGroup, tests each element's fields.
      on_value = operator_object?(condition) && condition.keys.none? { |k| CONDITION_OPERATORS.include?(k) }
      # @type var result: bool?
      result = false
      attribute_value.each do |item|
        next if item.nil?

        r = on_value ? eval_condition_value(condition, item, ctx) : eval_condition_result(item, condition, ctx)
        return true if r == true

        result = nil if r.nil?
      end
      result
    end

    # Only two numbers or two strings can be ordered; anything else is a type mismatch
    def self.orderable?(val1, val2)
      (number?(val1) && number?(val2)) || (val1.is_a?(String) && val2.is_a?(String))
    end

    def self.number?(value)
      value.is_a?(Integer) || value.is_a?(Float)
    end

    # On a type mismatch $vne matches and every other version operator fails
    def self.eval_version_operator(operator, attribute_value, condition_value)
      return operator == '$vne' unless orderable?(attribute_value, condition_value)

      a = padded_version_string(attribute_value)
      b = padded_version_string(condition_value)
      case operator
      when '$veq' then a == b
      when '$vne' then a != b
      when '$vgt' then a > b
      when '$vgte' then a >= b
      when '$vlt' then a < b
      when '$vlte' then a <= b
      else false
      end
    end

    def self.eval_compare_operator(operator, attribute_value, condition_value)
      case operator
      when '$eq' then strict_equal?(attribute_value, condition_value)
      when '$ne' then !strict_equal?(attribute_value, condition_value)
      else
        return false unless orderable?(attribute_value, condition_value)

        case operator
        when '$lt' then attribute_value < condition_value
        when '$lte' then attribute_value <= condition_value
        when '$gt' then attribute_value > condition_value
        when '$gte' then attribute_value >= condition_value
        else false
        end
      end
    end

    # Values of different types are never equal (no "5" == 5 or 0 == nil)
    def self.strict_equal?(val1, val2)
      get_type(val1) == get_type(val2) && val1 == val2
    end

    # Gets the values of a saved group for $inGroup/$notInGroup: a bare array, or
    # the values of a typed list entry. nil when it has no values to check.
    def self.saved_group_values(saved_groups, id)
      # An unknown id has always behaved like an empty list. A malformed entry
      # has not, and must not: $notInGroup would pass everyone.
      return [] unless saved_groups.key?(id)

      entry = saved_groups[id]
      return entry if entry.is_a?(Array)
      # These operators take their attribute from the condition they sit on
      return entry['values'].is_a?(Array) ? entry['values'] : nil if entry.is_a?(Hash) && entry['type'] == 'list'

      # A condition group, a malformed entry, or an unknown type
      nil
    end

    # A saved group type added after this SDK was built
    def self.new_group_type?(entry)
      entry.is_a?(Hash) && !%w[list condition].include?(entry['type'])
    end

    def self.eval_operator_condition(operator, attribute_value, condition_value, ctx)
      case operator
      when '$veq', '$vne', '$vgt', '$vgte', '$vlt', '$vlte'
        eval_version_operator(operator, attribute_value, condition_value)
      when '$eq', '$ne', '$lt', '$lte', '$gt', '$gte'
        eval_compare_operator(operator, attribute_value, condition_value)
      when '$regex'
        return false unless attribute_value.is_a?(String)

        silence_warnings do
          re = Regexp.new(condition_value)
          !!attribute_value.match(re)
        rescue StandardError
          false
        end
      when '$regexi'
        return false unless attribute_value.is_a?(String)

        silence_warnings do
          re = Regexp.new(condition_value, Regexp::IGNORECASE)
          !!attribute_value.match(re)
        rescue StandardError
          false
        end
      when '$in'
        return false unless condition_value.is_a?(Array)

        in?(attribute_value, condition_value)
      when '$nin'
        return false unless condition_value.is_a?(Array)

        !in?(attribute_value, condition_value)
      when '$ini'
        return false unless condition_value.is_a?(Array)

        in?(attribute_value, condition_value, insensitive: true)
      when '$nini'
        return false unless condition_value.is_a?(Array)

        !in?(attribute_value, condition_value, insensitive: true)
      when '$inGroup', '$notInGroup'
        entry = condition_value.is_a?(String) ? ctx.saved_groups[condition_value] : nil
        return nil if new_group_type?(entry)

        # No values means matching nobody. An empty list would pass everyone.
        values = condition_value.is_a?(String) ? saved_group_values(ctx.saved_groups, condition_value) : nil
        return false if values.nil?

        operator == '$inGroup' ? in?(attribute_value, values) : !in?(attribute_value, values)
      when '$elemMatch'
        elem_match(condition_value, attribute_value, ctx)
      when '$size'
        return false unless attribute_value.is_a? Array

        eval_condition_value(condition_value, attribute_value.length, ctx)
      when '$all'
        return false unless condition_value.is_a?(Array)

        in_all?(condition_value, attribute_value, ctx, false)
      when '$alli'
        return false unless condition_value.is_a?(Array)

        in_all?(condition_value, attribute_value, ctx, true)
      when '$exists'
        exists = !attribute_value.nil?
        if condition_value
          exists
        else
          !exists
        end
      when '$type'
        condition_value == get_type(attribute_value)
      when '$not'
        negate(eval_condition_value(condition_value, attribute_value, ctx))
      else
        # Keys this SDK knows, but on a condition rather than on a value, where
        # they never match. Any other operator is unsupported.
        CONDITION_OPERATORS.include?(operator) ? false : nil
      end
    end

    def self.in_all?(condition_values, attribute_value, ctx, insensitive)
      return false unless attribute_value.is_a? Array

      # @type var result: bool?
      result = true
      condition_values.each do |cond|
        # @type var passed: bool?
        passed = false
        attribute_value.each do |attr|
          r = eval_condition_value(cond, attr, ctx, insensitive: insensitive)
          if r == true
            passed = true
            break
          end
          passed = nil if r.nil?
        end
        return false if passed == false

        result = nil if passed.nil?
      end
      result
    end

    def self.padded_version_string(input)
      # Format numbers like JS does (2.0 -> "2", 0.000002 -> "0.000002"); treat empty input as version 0
      input = Util.js_number_to_s(input) if number?(input)
      input = '0' if input.empty?

      # Remove build info and leading `v` if any
      # Split version into parts (both core version numbers and pre-release tags)
      # "v1.2.3-rc.1+build123" -> ["1","2","3","rc","1"]
      parts = input.gsub(/(^v|\+.*$)/, '').split(/[-.]/)

      # If it's SemVer without a pre-release, add `~` to the end
      # ["1","0","0"] -> ["1","0","0","~"]
      # "~" is the largest ASCII character, so this will make "1.0.0" greater than "1.0.0-beta" for example
      parts << '~' if parts.length == 3

      # Left pad each numeric part with spaces so string comparisons will work ("9">"10", but " 9"<"10")
      parts.map do |part|
        /^[0-9]+$/.match?(part) ? part.rjust(5, ' ') : part
      end.join('-')
    end

    def self.in?(actual, expected, insensitive: false)
      expected ||= []

      if insensitive
        fold = ->(val) { val.is_a?(String) ? val.downcase : val }
        folded_expected = expected.map { |exp| fold.call(exp) }
        return actual.any? { |el| folded_expected.include?(fold.call(el)) } if actual.is_a?(Array)

        return folded_expected.include?(fold.call(actual))
      end

      return expected.include?(actual) unless actual.is_a?(Array)

      (actual & expected).any?
    end

    # Sets $VERBOSE for the duration of the block and back to its original
    # value afterwards. Used for testing invalid regexes.
    def self.silence_warnings
      old_verbose = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = old_verbose
    end
  end
end
