# frozen_string_literal: true

# The GrowthBook SDK
module Growthbook
  # Partially evaluate a targeting condition when only some attributes are known,
  # e.g. on a server. Attributes missing from `attributes` are unknown.
  #
  # @param attributes [Hash] The known attributes
  # @param condition [Hash] The targeting condition
  # @param saved_groups [Hash] The payload's saved groups
  # @return [true, false, Hash] true or false once the result can't depend on the
  #   unknown attributes, otherwise the condition minus every branch already decided
  def self.prune_condition(attributes, condition, saved_groups = {})
    Growthbook::Conditions.prune_condition(
      Growthbook::Conditions.parse_condition(attributes || {}),
      Growthbook::Conditions.parse_condition(condition),
      saved_groups || {}
    )
  end
end

require 'growthbook/conditions'
require 'growthbook/context'
require 'growthbook/decryption_util'
require 'growthbook/feature'
require 'growthbook/feature_repository'
require 'growthbook/feature_result'
require 'growthbook/feature_rule'
require 'growthbook/fnv'
require 'growthbook/inline_experiment'
require 'growthbook/inline_experiment_result'
require 'growthbook/tracking_callback'
require 'growthbook/util'
require 'growthbook/feature_usage_callback'
require 'growthbook/sticky_bucket_service'
