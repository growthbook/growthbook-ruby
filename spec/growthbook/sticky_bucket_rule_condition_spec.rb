# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

# Ported from growthbook-php#91 and growthbook-python (issue #161). The JS SDK
# checks a rule's condition up front only for force rules; experiment rules
# check it after the sticky bucket lookup, so sticky users keep their variation.
describe 'sticky bucketing and rule conditions' do
  let(:attributes) { { 'id' => 'user-8', 'country' => 'US' } }
  let(:force_rule) { { 'force' => 'forced' } }

  def experiment_rule(countries, extra = {})
    {
      'key'           => 'checkout-exp',
      'variations'    => %w[old new],
      'meta'          => [{ 'key' => '0' }, { 'key' => '1' }],
      'hashAttribute' => 'id',
      'hashVersion'   => 2,
      'condition'     => { 'country' => { '$in' => countries } }
    }.merge(extra)
  end

  def eval_feature(rules, extra_features: {}, **options)
    features = { 'f' => { 'defaultValue' => 'old', 'rules' => rules } }.merge(extra_features)
    Growthbook::Context.new(features: features, attributes: attributes, **options).eval_feature('f')
  end

  # A sticky bucket service where the user is already bucketed into "new"
  def sticky_bucket_service
    service = Growthbook::InMemoryStickyBucketService.new
    result = eval_feature([experiment_rule(%w[US CA])], sticky_bucket_service: service)
    raise 'expected the user to be bucketed into "new"' unless result.value == 'new'

    service
  end

  it 'keeps a sticky-bucketed user in the experiment when the rule condition no longer matches' do
    result = eval_feature([experiment_rule(%w[CA])], sticky_bucket_service: sticky_bucket_service)

    expect([result.value, result.source, result.experiment_result.sticky_bucket_used?]).to eq(['new', 'experiment', true])
  end

  it 'prefers the sticky bucket over a later force rule' do
    result = eval_feature([experiment_rule(%w[CA]), force_rule], sticky_bucket_service: sticky_bucket_service)

    expect([result.value, result.source]).to eq(%w[new experiment])
  end

  it 'applies a forced variation even when the rule condition does not match' do
    result = eval_feature([experiment_rule(%w[CA])], forced_variations: { 'checkout-exp' => 1 })

    expect([result.value, result.source]).to eq(%w[new experiment])
  end

  it 'still applies the experiment rule condition without a sticky bucket' do
    result = eval_feature([experiment_rule(%w[CA]), force_rule])

    expect([result.value, result.source]).to eq(%w[forced force])
  end

  it 'still applies the force rule condition' do
    result = eval_feature([force_rule.merge('condition' => { 'country' => 'CA' })])

    expect([result.value, result.source]).to eq(%w[old defaultValue])
  end

  it 'still applies rule filters with a sticky bucket' do
    filters = { 'filters' => [{ 'seed' => 's', 'ranges' => [[0, 0]], 'attribute' => 'id' }] }
    result = eval_feature([experiment_rule(%w[US CA], filters)], sticky_bucket_service: sticky_bucket_service)

    expect([result.value, result.source]).to eq(%w[old defaultValue])
  end

  it 'still applies rule prerequisites with a sticky bucket' do
    prerequisites = { 'parentConditions' => [{ 'id' => 'parent', 'condition' => { 'value' => true } }] }
    result = eval_feature(
      [experiment_rule(%w[US CA], prerequisites)],
      extra_features: { 'parent' => { 'defaultValue' => false } },
      sticky_bucket_service: sticky_bucket_service
    )

    expect([result.value, result.source]).to eq(%w[old defaultValue])
  end
end
