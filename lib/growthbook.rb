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

  # Shrink a features payload for a user whose attributes are only partly known,
  # e.g. on a server that bootstraps a client-side SDK. The result evaluates the
  # same as the full payload for anyone who agrees with the known attributes.
  #
  # @param payload [Hash] A decrypted features payload, as returned by the SDK API
  #   (features, experiments, savedGroups, contextualBandits)
  # @param attributes [Hash] The attributes known for the user
  # @param include [Hash] Keep only features and experiments that match every filter:
  #   `projects`, `tags` (arrays, any one value is enough) and `customFields` (a hash of field to array of values)
  # @param exclude [Hash] Drop features and experiments that match any filter, with the same keys as `include`
  # @param prerequisites ['keep', 'filter'] With 'keep' (the default), the prerequisites of kept features and
  #   experiments are kept even when the filters drop them. With 'filter', only holdouts are.
  # @return [Hash] The reduced payload, with every other key of `payload` unchanged
  def self.reduce_payload(payload, attributes: {}, include: {}, exclude: {}, prerequisites: 'keep')
    Growthbook::PayloadReducer.new(
      Growthbook::Conditions.parse_condition(payload),
      attributes: Growthbook::Conditions.parse_condition(attributes || {}),
      include: payload_filters(include),
      exclude: payload_filters(exclude),
      prerequisites: prerequisites
    ).reduce
  end

  # Filters with string keys, accepting `custom_fields` for `customFields`
  def self.payload_filters(filters)
    filters = Growthbook::Conditions.parse_condition(filters || {})
    filters['customFields'] = filters.delete('custom_fields') if filters.key?('custom_fields')
    filters
  end
  private_class_method :payload_filters
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
require 'growthbook/payload_reducer'
require 'growthbook/tracking_callback'
require 'growthbook/util'
require 'growthbook/feature_usage_callback'
require 'growthbook/sticky_bucket_service'
