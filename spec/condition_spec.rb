# frozen_string_literal: true

require 'spec_helper'
require 'growthbook'

describe 'conditions' do
  context 'when condition keys have symbols' do
    it 'handles conditions with mixed symbol/string keys' do
      gb = Growthbook::Context.new(
        {
          attributes: {
            'id' => 5
          },
          features: {
            feature: {
              defaultValue: false,
              rules: [
                {
                  force: true,
                  condition: {
                    '$and' => [
                      {
                        # Using symbols for hash keys
                        id: { '$gt' => 4 }
                      },
                      {
                        id: { '$lt' => 10 }
                      }
                    ]
                  }
                }
              ]
            }
          }
        }
      )

      result = gb.eval_feature('feature')

      expect(result.on).to be(true)
    end
  end

  context 'with an explicit null attributeKey' do
    it 'does not fall back to the group attribute' do
      saved_groups = { 'g' => { 'type' => 'list', 'attributeKey' => 'id', 'values' => ['u'] } }
      condition = { '$savedGroup' => { 'id' => 'g', 'attributeKey' => nil } }
      expect(Growthbook::Conditions.eval_condition({ 'id' => 'u' }, condition, saved_groups)).to be(false)
      expect(Growthbook::Conditions.eval_condition({ 'id' => 'u' }, { '$savedGroup' => { 'id' => 'g' } }, saved_groups)).to be(true)
    end
  end

  context 'with a null literal condition' do
    it 'does not match NaN or infinity' do
      [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |value|
        expect(Growthbook::Conditions.eval_condition({ 'a' => value }, { 'a' => nil })).to be(false)
      end
      expect(Growthbook::Conditions.eval_condition({ 'a' => nil }, { 'a' => nil })).to be(true)
      expect(Growthbook::Conditions.eval_condition({}, { 'a' => nil })).to be(true)
    end
  end

  context 'with numeric version operands' do
    it 'formats numbers like JavaScript' do
      expect(Growthbook::Conditions.eval_condition({ 'a' => 0.000002 }, { 'a' => { '$vgt' => 1.5 } })).to be(false)
      expect(Growthbook::Conditions.eval_condition({ 'a' => 0.000002 }, { 'a' => { '$vlt' => 1.5 } })).to be(true)
      { 1e21 => '1e+21', 1e20 => '100000000000000000000', 2.0 => '2', 1e-7 => '1e-7' }.each do |number, string|
        expect(Growthbook::Conditions.padded_version_string(number)).to eq(Growthbook::Conditions.padded_version_string(string))
      end
    end
  end
end
