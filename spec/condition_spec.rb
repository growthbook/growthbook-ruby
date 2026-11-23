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

  context 'with a version prefix or build metadata' do
    def padded(input)
      Growthbook::Conditions.padded_version_string(input)
    end

    it 'strips one leading v and everything from the first +' do
      plain = padded('1.2.3')
      expect(padded('v1.2.3')).to eq(plain)
      expect(padded('vv1.2.3')).to eq('v1-    2-    3-~')
      expect(padded('1.2.3+build')).to eq(plain)
      expect(padded('v1.2.3+build+more.1-2')).to eq(plain)
      expect(padded('1.2.3+')).to eq(plain)
      expect(padded('+build')).to eq('')
      expect(padded('v1.2.3-rc.1+build.5')).to eq(padded('1.2.3-rc.1'))
    end

    it 'treats line breaks as ordinary characters, like JS' do
      # `^` and `$` match at line breaks in Ruby, so the regex kept "\nx" and stripped a `v` after a line break
      expect(padded("1.2.3+build\nx")).to eq(padded('1.2.3'))
      expect(padded("1.2.3+\n")).to eq(padded('1.2.3'))
      expect(padded("x\nv1.2.3")).to eq("x\nv1-    2-    3-~")
      expect(padded("1\n.2.3")).to eq("1\n-    2-    3-~")
    end

    it 'keeps a trailing empty part, like JS split' do
      # "1.2.3-" has four parts, so it isn't padded with `~` like "1.2.3"
      expect(padded('1.2.3-')).to eq('    1-    2-    3-')
      expect(padded('1.2.3.')).to eq('    1-    2-    3-')
      expect(Growthbook::Conditions.eval_condition({ 'v' => '1.2.3-' }, { 'v' => { '$veq' => '1.2.3' } })).to be(false)
    end

    it 'runs in linear time on many + characters' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      padded("#{'+' * 50_000}\n")
      padded("#{'+' * 50_000}\nx")
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.5
    end
  end

  context 'with array or object operands' do
    it 'never matches them, as JS compares by reference' do
      [[], [1], {}, { 'a' => 1 }].each do |value|
        expect(Growthbook::Conditions.eval_condition({ 'a' => value }, { 'a' => { '$eq' => value } })).to be(false)
        expect(Growthbook::Conditions.eval_condition({ 'a' => value }, { 'a' => { '$ne' => value } })).to be(true)
        expect(Growthbook::Conditions.eval_condition({ 'a' => value }, { 'a' => { '$in' => [value] } })).to be(false)
        expect(Growthbook::Conditions.eval_condition({ 'a' => value }, { 'a' => { '$nin' => [value] } })).to be(true)
        expect(Growthbook::Conditions.eval_condition({ 'a' => value }, { 'a' => { '$ini' => [value] } })).to be(false)
      end
    end
  end

  context 'with integer and float values' do
    it 'compares numbers by value inside arrays and saved groups' do
      expect(Growthbook::Conditions.eval_condition({ 'a' => [1] }, { 'a' => { '$in' => [1.0] } })).to be(true)
      expect(Growthbook::Conditions.eval_condition({ 'a' => [1.0] }, { 'a' => { '$nin' => [1] } })).to be(false)
      groups = { 'nums' => [1.0, 2] }
      expect(Growthbook::Conditions.eval_condition({ 'a' => [1] }, { 'a' => { '$inGroup' => 'nums' } }, groups)).to be(true)
      expect(Growthbook::Conditions.eval_condition({ 'a' => 2.0 }, { 'a' => { '$notInGroup' => 'nums' } }, groups)).to be(false)
    end
  end

  context 'with a path through an array' do
    it 'indexes into the array like JS' do
      expect(Growthbook::Conditions.eval_condition({ 'tags' => %w[a b] }, { 'tags.1' => 'b' })).to be(true)
      expect(Growthbook::Conditions.eval_condition({ 'tags' => %w[a b] }, { 'tags.length' => 2 })).to be(true)
      expect(Growthbook::Conditions.eval_condition({ 'tags' => %w[a b] }, { 'tags.2' => { '$exists' => false } })).to be(true)
      expect(Growthbook::Conditions.eval_condition({ 'tags' => %w[a b] }, { 'tags.01' => { '$exists' => false } })).to be(true)
    end
  end

  context 'with non-ASCII strings' do
    it 'orders them by UTF-16 code units like JS' do
      expect(Growthbook::Conditions.eval_condition({ 'a' => "\u{1F600}" }, { 'a' => { '$lt' => "\uFFFF" } })).to be(true)
      expect(Growthbook::Conditions.eval_condition({ 'a' => "\uFFFF" }, { 'a' => { '$gt' => "\u{1F600}" } })).to be(true)
    end
  end

  context 'with a non-string regex pattern' do
    it 'does not match' do
      [1, nil, true, ['a'], { 'a' => 1 }].each do |pattern|
        expect(Growthbook::Conditions.eval_condition({ 'a' => '1' }, { 'a' => { '$regex' => pattern } })).to be(false)
        expect(Growthbook::Conditions.eval_condition({ 'a' => '1' }, { 'a' => { '$regexi' => pattern } })).to be(false)
      end
    end
  end
end
