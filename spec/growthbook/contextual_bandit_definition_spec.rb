# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

RSpec.describe Growthbook::ContextualBanditDefinition do
  describe '.initialize' do
    subject(:definition) do
      described_class.new(
        'banditVersion' => 7,
        'contexts'      => [
          { 'leafId' => 1, 'condition' => { 'plan' => 'pro' }, 'weights' => [0.9, 0.1] }
        ]
      )
    end

    its(:bandit_version) { is_expected.to eq(7) }

    it 'parses the leaves' do
      leaf = definition.contexts.first

      expect(leaf.leaf_id).to eq(1)
      expect(leaf.weights).to eq([0.9, 0.1])
      expect(leaf.condition).to eq('plan' => 'pro')
    end

    it 'accepts symbol keys' do
      definition = described_class.new(bandit_version: 3, contexts: [{ leaf_id: 2, weights: [1, 0] }])

      expect(definition.bandit_version).to eq(3)
      expect(definition.contexts.first.leaf_id).to eq(2)
    end

    it 'coerces a numeric bandit version' do
      expect(described_class.new('banditVersion' => '9').bandit_version).to eq(9)
    end

    it 'leaves the bandit version unset when absent' do
      expect(described_class.new('contexts' => []).bandit_version).to be_nil
    end

    it 'tolerates a missing contexts array' do
      expect(described_class.new('banditVersion' => 1).contexts).to eq([])
    end

    it 'tolerates a definition that is not a hash' do
      expect(described_class.new(nil).contexts).to eq([])
    end

    it 'keeps already parsed leaves as they are' do
      leaf = Growthbook::ContextualBanditContext.new('leafId' => 5)
      definition = described_class.new('contexts' => [leaf])

      expect(definition.contexts.first).to be(leaf)
    end
  end
end
