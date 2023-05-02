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
end
