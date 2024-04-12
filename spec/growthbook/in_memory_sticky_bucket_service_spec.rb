# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

describe Growthbook::InMemoryStickyBucketService do
  # Start forcing everyone to variation1
  features = {
    'feature' => {
      'defaultValue' => 5,
      'rules'        => [{
        'key'        => 'exp',
        'variations' => [0, 1],
        'weights'    => [0, 1],
        'meta'       => [
          { 'key' => 'control' },
          { 'key' => 'variation1' }
        ]
      }]
    }
  }

  it 'gets and saves assignments' do
    service = described_class.new
    gb = Growthbook::Context.new(
      sticky_bucket_service: service,
      attributes: {
        'id' => '1'
      },
      features: features
    )

    expect(gb.feature_value('feature', -1)).to eq(1)
    expect(service.get_assignments('id', '1')).to eq(
      {
        'attributeName'  => 'id',
        'attributeValue' => '1',
        'assignments'    => {
          'exp__0' => 'variation1'
        }
      }
    )

    features['feature']['rules'][0]['weights'] = [1, 0]
    gb.features = features
    expect(gb.feature_value('feature', -1)).to eq(1)

    gb2 = Growthbook::Context.new(
      sticky_bucket_service: service,
      attributes: {
        'id' => '1'
      },
      features: features
    )
    expect(gb2.feature_value('feature', -1)).to eq(1)

    gb.attributes = { 'id' => '2' }
    expect(gb.feature_value('feature', -1)).to eq(0)

    gb.attributes = { 'id' => '1' }
    features['feature']['rules'][0]['bucketVersion'] = 1
    gb.features = features
    expect(gb.feature_value('feature', -1)).to eq(0)

    expect(service.get_assignments('id', '1')).to eq(
      {
        'attributeName'  => 'id',
        'attributeValue' => '1',
        'assignments'    => {
          'exp__0' => 'variation1',
          'exp__1' => 'control'
        }
      }
    )
  end
end
