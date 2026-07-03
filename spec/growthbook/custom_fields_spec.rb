# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

RSpec.describe 'customFields' do
  describe Growthbook::InlineExperiment do
    it 'reads custom_fields from options' do
      exp = described_class.new(variations: [0, 1], custom_fields: { 'team' => 'growth' })
      expect(exp.custom_fields).to eq('team' => 'growth')
    end

    it 'accepts the camelCase customFields key' do
      exp = described_class.new(variations: [0, 1], customFields: { 'team' => 'growth' })
      expect(exp.custom_fields).to eq('team' => 'growth')
    end

    it 'defaults to nil when absent' do
      exp = described_class.new(variations: [0, 1])
      expect(exp.custom_fields).to be_nil
    end
  end

  describe Growthbook::FeatureRule do
    it 'reads custom_fields and forwards them to the experiment' do
      rule = described_class.new(
        'variations'   => [0, 1],
        'customFields' => { 'owner' => 'team-a', 'priority' => 3 }
      )

      expect(rule.custom_fields).to eq('owner' => 'team-a', 'priority' => 3)
      expect(rule.to_experiment('my-feature').custom_fields).to eq('owner' => 'team-a', 'priority' => 3)
    end

    it 'defaults to nil when absent' do
      rule = described_class.new('variations' => [0, 1])
      expect(rule.custom_fields).to be_nil
    end
  end
end
