# frozen_string_literal: true

module Growthbook
  # How a contextual bandit routed one evaluation: the leaf that matched, the
  # weights it supplied and the weight generation they came from.
  #
  # Reported on the experiment and its result so an exposure can be attributed to
  # the weights that produced it.
  class ContextualBandit
    # Recorded when a bandit definition was found but none of its leaves matched
    # the user, so the experiment's own (or equal) weights were used
    FALLBACK_LEAF_ID = -1

    # @return [Integer] The matching leaf, or FALLBACK_LEAF_ID
    attr_reader :leaf_id

    # @return [Float[]] The weights the user was bucketed with
    attr_reader :variation_weights

    # @return [Integer, nil] Version of the backend-computed weights
    attr_reader :bandit_version

    def initialize(leaf_id, variation_weights, bandit_version = nil)
      @leaf_id = leaf_id
      @variation_weights = variation_weights
      @bandit_version = bandit_version
    end

    def to_json(*_args)
      {
        'leafId'           => @leaf_id,
        'variationWeights' => @variation_weights,
        'banditVersion'    => @bandit_version
      }.compact
    end
  end

  # One leaf of a contextual bandit: a targeting condition and the variation
  # weights to bucket with when it matches.
  class ContextualBanditContext
    # @return [Integer, nil] Identifies the leaf in reporting
    attr_reader :leaf_id

    # @return [Hash, nil] Targeting condition evaluated against the user attributes
    attr_reader :condition

    # @return [Float[], nil] Weights to use when this leaf matches
    attr_reader :weights

    def initialize(context)
      context = {} unless context.is_a?(Hash)

      @leaf_id = get_option(context, :leaf_id) || get_option(context, :leafId)
      @weights = get_option(context, :weights)

      cond = get_option(context, :condition)
      @condition = cond.nil? ? nil : Growthbook::Conditions.parse_condition(cond)
    end

    private

    def get_option(hash, key)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      nil
    end
  end

  # A contextual bandit shipped in the feature payload under `contextualBandits`,
  # keyed by the `contextualBanditRef` a feature rule points at.
  #
  # All the optimisation happens on the GrowthBook backend: the definition is a
  # read-only input, and the SDK only picks the leaf that matches the user and
  # buckets with its weights.
  class ContextualBanditDefinition
    # @return [Integer, nil] Version of the backend-computed weights
    attr_reader :bandit_version

    # @return [Growthbook::ContextualBanditContext[]] Leaves, in the order they are evaluated
    attr_reader :contexts

    def initialize(definition)
      definition = {} unless definition.is_a?(Hash)

      version = get_option(definition, :bandit_version) || get_option(definition, :banditVersion)
      @bandit_version = version&.to_i

      contexts = get_option(definition, :contexts)
      @contexts = (contexts.is_a?(Array) ? contexts : []).map do |context|
        context.is_a?(Growthbook::ContextualBanditContext) ? context : Growthbook::ContextualBanditContext.new(context)
      end
    end

    private

    def get_option(hash, key)
      return hash[key.to_sym] if hash.key?(key.to_sym)
      return hash[key.to_s] if hash.key?(key.to_s)

      nil
    end
  end
end
