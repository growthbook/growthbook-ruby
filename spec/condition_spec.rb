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

end
