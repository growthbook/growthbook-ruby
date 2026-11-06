# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

RSpec.describe Growthbook::ContextualBandit do
  it 'serializes the routing metadata' do
    bandit = described_class.new(2, [0.3, 0.7], 4)

    expect(bandit.to_json).to eq('leafId' => 2, 'variationWeights' => [0.3, 0.7], 'banditVersion' => 4)
  end

  it 'omits a missing bandit version' do
    expect(described_class.new(2, [1, 0]).to_json).to eq('leafId' => 2, 'variationWeights' => [1, 0])
  end

  it 'uses -1 as the fallback leaf' do
    expect(described_class::FALLBACK_LEAF_ID).to eq(-1)
  end
end
