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

  # Expected values below were generated with the JS SDK's evalCondition (mongrule.ts)

  context 'when the condition is a plain string' do
    [
      ['coerces an integer attribute', { 'x' => '10' }, { 'x' => 10 }, true],
      ['coerces a float attribute', { 'x' => '1.5' }, { 'x' => 1.5 }, true],
      ['drops the trailing .0 of a float attribute', { 'x' => '10' }, { 'x' => 10.0 }, true],
      ['uses JS exponent notation for large floats', { 'x' => '1e+21' }, { 'x' => 1e21 }, true],
      ['uses JS fixed notation below 1e21', { 'x' => '100000000000000000000' }, { 'x' => 1e20 }, true],
      ['uses JS exponent notation for tiny floats', { 'x' => '1e-7' }, { 'x' => 1e-7 }, true],
      ['uses JS fixed notation for 0.000001', { 'x' => '0.000001' }, { 'x' => 0.000001 }, true],
      ['coerces a boolean attribute', { 'x' => 'true' }, { 'x' => true }, true],
      ['coerces a false attribute', { 'x' => 'false' }, { 'x' => false }, true],
      ['matches "null" against a null attribute', { 'x' => 'null' }, { 'x' => nil }, true],
      ['matches "null" against a missing attribute', { 'x' => 'null' }, {}, true],
      ['does not match "undefined" against a missing attribute', { 'x' => 'undefined' }, {}, false],
      ['does not match an empty string against null', { 'x' => '' }, { 'x' => nil }, false],
      ['joins an array attribute with commas', { 'x' => 'a,b' }, { 'x' => %w[a b] }, true],
      ['joins null array elements as empty strings', { 'x' => '1,,2' }, { 'x' => [1, nil, 2] }, true],
      ['stringifies an object attribute', { 'x' => '[object Object]' }, { 'x' => { 'a' => 1 } }, true]
    ].each do |name, condition, attributes, expected|
      it name do
        expect(Growthbook::Conditions.eval_condition(attributes, condition)).to be(expected)
      end
    end
  end

  context 'when the condition is a plain number' do
    [
      ['coerces a numeric string attribute', { 'x' => 10 }, { 'x' => '10' }, true],
      ['trims whitespace in a string attribute', { 'x' => 10 }, { 'x' => ' 10 ' }, true],
      ['parses exponent strings', { 'x' => 10 }, { 'x' => '1e1' }, true],
      ['parses decimal strings', { 'x' => 10 }, { 'x' => '10.0' }, true],
      ['parses hex strings', { 'x' => 26 }, { 'x' => '0x1A' }, true],
      ['does not match a non-numeric string', { 'x' => 10 }, { 'x' => 'abc' }, false],
      ['treats an empty string as 0', { 'x' => 0 }, { 'x' => '' }, true],
      ['treats true as 1', { 'x' => 1 }, { 'x' => true }, true],
      ['treats false as 0', { 'x' => 0 }, { 'x' => false }, true],
      ['treats null as 0', { 'x' => 0 }, { 'x' => nil }, true],
      ['treats a missing attribute as null', { 'x' => 0 }, {}, true],
      ['matches an integer condition against a float attribute', { 'x' => 1 }, { 'x' => 1.0 }, true],
      ['matches a float condition against an integer attribute', { 'x' => 1.0 }, { 'x' => 1 }, true],
      ['coerces a single-element array', { 'x' => 5 }, { 'x' => [5] }, true],
      ['treats an empty array as 0', { 'x' => 0 }, { 'x' => [] }, true]
    ].each do |name, condition, attributes, expected|
      it name do
        expect(Growthbook::Conditions.eval_condition(attributes, condition)).to be(expected)
      end
    end
  end

  context 'when the condition is a plain boolean' do
    [
      ['treats "false" as truthy', { 'x' => true }, { 'x' => 'false' }, true],
      ['treats "0" as truthy', { 'x' => true }, { 'x' => '0' }, true],
      ['treats 0 as falsy', { 'x' => false }, { 'x' => 0 }, true],
      ['treats an empty string as falsy', { 'x' => false }, { 'x' => '' }, true],
      ['treats a non-zero number as truthy', { 'x' => true }, { 'x' => 2 }, true],
      ['treats an empty array as truthy', { 'x' => true }, { 'x' => [] }, true],
      ['treats an empty object as truthy', { 'x' => true }, { 'x' => {} }, true],
      ['never matches a null attribute', { 'x' => false }, { 'x' => nil }, false],
      ['never matches a missing attribute', { 'x' => false }, {}, false]
    ].each do |name, condition, attributes, expected|
      it name do
        expect(Growthbook::Conditions.eval_condition(attributes, condition)).to be(expected)
      end
    end
  end

  context 'when the condition is null, an array or a plain object' do
    [
      ['null matches a missing attribute', { 'x' => nil }, {}, true],
      ['null does not match 0', { 'x' => nil }, { 'x' => 0 }, false],
      ['array matches an equal array', { 'x' => [1, 2] }, { 'x' => [1, 2] }, true],
      ['array does not match a reordered array', { 'x' => [1, 2] }, { 'x' => [2, 1] }, false],
      ['object matches an equal object', { 'x' => { 'a' => 1 } }, { 'x' => { 'a' => 1 } }, true]
    ].each do |name, condition, attributes, expected|
      it name do
        expect(Growthbook::Conditions.eval_condition(attributes, condition)).to be(expected)
      end
    end
  end

  context 'when $alli compares case-insensitively' do
    [
      ['folds case', { 'x' => { '$alli' => ['A'] } }, { 'x' => ['a'] }, true],
      ['coerces non-string elements', { 'x' => { '$alli' => ['1'] } }, { 'x' => [1] }, true]
    ].each do |name, condition, attributes, expected|
      it name do
        expect(Growthbook::Conditions.eval_condition(attributes, condition)).to be(expected)
      end
    end
  end

  context 'when a version operator gets a non-string attribute' do
    [
      ['$veq treats a missing attribute as 0', { 'v' => { '$veq' => '0' } }, {}, true],
      ['$veq treats null as 0', { 'v' => { '$veq' => '0' } }, { 'v' => nil }, true],
      ['$vlt treats a missing attribute as below any release', { 'v' => { '$vlt' => '0.0.1' } }, {}, true],
      ['$vgt is false for a missing attribute', { 'v' => { '$vgt' => '1.0.0' } }, {}, false],
      ['$vne treats a missing attribute as different', { 'v' => { '$vne' => '1.0.0' } }, {}, true],
      ['$vgt stringifies an integer attribute', { 'v' => { '$vgt' => '1.2.0' } }, { 'v' => 2 }, true],
      ['$vgt stringifies a float attribute', { 'v' => { '$vgt' => '1.9' } }, { 'v' => 1.1 }, false],
      ['$veq splits a float attribute on the decimal point', { 'v' => { '$veq' => '1.5' } }, { 'v' => 1.5 }, true],
      ['$vlte stringifies an integer attribute', { 'v' => { '$vlte' => '1' } }, { 'v' => 1 }, true],
      ['$veq treats true as 0', { 'v' => { '$veq' => '0' } }, { 'v' => true }, true],
      ['$vgte treats false as 0', { 'v' => { '$vgte' => '0' } }, { 'v' => false }, true],
      ['$veq treats an array as 0', { 'v' => { '$veq' => '0' } }, { 'v' => [1, 2] }, true],
      ['$veq treats an empty string as 0', { 'v' => { '$veq' => '0' } }, { 'v' => '' }, true],
      ['$veq only strips a leading v at the start of the string', { 'v' => { '$veq' => "x\n1.2.3" } }, { 'v' => "x\nv1.2.3" }, false]
    ].each do |name, condition, attributes, expected|
      it name do
        expect(Growthbook::Conditions.eval_condition(attributes, condition)).to be(expected)
      end
    end

    it 'does not raise from eval_feature' do
      gb = Growthbook::Context.new(
        attributes: {},
        features: {
          feature: {
            defaultValue: 0,
            rules: [{ condition: { 'v' => { '$vgt' => '1.0.0' } }, force: 1 }]
          }
        }
      )

      expect(gb.eval_feature('feature').value).to eq(0)
    end
  end
end
