# frozen_string_literal: true

require 'spec_helper'
require 'growthbook'

RSpec.describe 'payload reduction' do
  describe '.prune_condition' do
    it 'accepts symbol keys' do
      expect(Growthbook.prune_condition({ id: '123' }, { id: '123', country: 'US' })).to eq({ 'country' => 'US' })
    end

    it 'compares numbers by value, like JavaScript' do
      expect(Growthbook.prune_condition({ 'a' => 1.0 }, { 'a' => 1 })).to be(true)
      expect(Growthbook.prune_condition({ 'a' => -0.0 }, { 'a' => 0 })).to be(true)
      expect(Growthbook.prune_condition({ 'a' => { 'b' => 1.0 } }, { 'a' => { 'b' => 1 } })).to be(true)
      expect(Growthbook.prune_condition({ 'a' => '1' }, { 'a' => 1 })).to be(false)
    end

    it 'does not match NaN or infinity to a null literal' do
      expect(Growthbook.prune_condition({ 'a' => Float::NAN }, { 'a' => nil })).to be(false)
      expect(Growthbook.prune_condition({ 'a' => Float::INFINITY }, { 'a' => nil })).to be(false)
      expect(Growthbook.prune_condition({ 'a' => nil }, { 'a' => nil })).to be(true)
    end

    it 'does not fall back to the group attribute for an explicit null attributeKey' do
      saved_groups = { 'g' => { 'type' => 'list', 'attributeKey' => 'id', 'values' => ['u'] } }
      condition = { '$savedGroup' => { 'id' => 'g', 'attributeKey' => nil } }
      expect(Growthbook.prune_condition({ 'id' => 'u' }, condition, saved_groups)).to be(false)
    end
  end

  describe '.reduce_payload' do
    let(:payload) do
      {
        'features' => {
          'android' => { 'defaultValue' => 1, 'metadata' => { 'customFields' => { 'platform' => ['android'] } } },
          'ios'     => { 'defaultValue' => 2, 'metadata' => { 'customFields' => { 'platform' => ['ios'] } } },
          'beta'    => { 'defaultValue' => false, 'rules' => [{ 'condition' => { 'id' => '123' }, 'force' => true }] }
        }
      }
    end

    it 'accepts symbol keys and custom_fields for customFields' do
      result = Growthbook.reduce_payload(payload, include: { custom_fields: { platform: ['android'] } })
      expect(result['features'].keys).to eq(['android'])
    end

    it 'does not modify the payload' do
      original = Marshal.load(Marshal.dump(payload))
      result = Growthbook.reduce_payload(payload, attributes: { id: '123' })
      expect(result['features']['beta']['rules']).to eq([{ 'force' => true }])
      expect(payload).to eq(original)
    end

    it 'keeps the rule of an integral float attribute that matches' do
      payload = { 'features' => { 'f' => { 'defaultValue' => false, 'rules' => [{ 'condition' => { 'a' => 1 }, 'force' => true }] } } }
      result = Growthbook.reduce_payload(payload, attributes: { a: 1.0 })
      expect(result['features']['f']['rules']).to eq([{ 'force' => true }])
    end

    it 'does not make a null literal rule unconditional for a NaN attribute' do
      payload = { 'features' => { 'f' => { 'defaultValue' => false, 'rules' => [{ 'condition' => { 'a' => nil }, 'force' => true }] } } }
      result = Growthbook.reduce_payload(payload, attributes: { a: Float::NAN })
      expect(result['features']['f']['rules']).to eq([{ 'condition' => { '$not' => {} }, 'force' => nil }])
    end

    it 'keeps a malformed condition group and its reference as written' do
      rules = [{ 'condition' => { '$savedGroup' => { 'id' => 'g' } }, 'force' => true }]
      payload = {
        'features'    => { 'f' => { 'defaultValue' => false, 'rules' => rules } },
        'savedGroups' => { 'g' => { 'type' => 'condition', 'condition' => { '$not' => nil } } }
      }
      result = Growthbook.reduce_payload(payload, attributes: {})
      expect(result['features']).to eq(payload['features'])
      expect(result['savedGroups']).to eq(payload['savedGroups'])
    end

    def condition_group(condition)
      { 'type' => 'condition', 'condition' => condition }
    end

    it 'reduces many condition groups that share a large list group' do
      ids = (1..20_000).map { |i| "user-#{i}" }
      saved_groups = { 'big' => { 'type' => 'list', 'attributeKey' => 'id', 'values' => ids } }
      rules = (1..300).map do |i|
        saved_groups["g#{i}"] = condition_group('country' => 'US', '$savedGroup' => { 'id' => 'big' })
        { 'condition' => { '$savedGroup' => { 'id' => "g#{i}" } }, 'force' => i }
      end
      payload = { 'features' => { 'f' => { 'defaultValue' => 0, 'rules' => rules } }, 'savedGroups' => saved_groups }

      result = Growthbook.reduce_payload(payload, attributes: { country: 'US' })

      expect(result['savedGroups'].keys).to match_array(saved_groups.keys)
      expect(result['savedGroups']['big']).to eq(saved_groups['big'])
      (1..300).each do |i|
        expect(result['savedGroups']["g#{i}"]['condition']).to eq({ '$savedGroup' => { 'id' => 'big' } })
      end
    end

    it 'keeps groups on a reference cycle as written and reduces the rest' do
      saved_groups = {
        'a'       => condition_group('country' => 'US', '$or' => [{ '$savedGroup' => { 'id' => 'b' } }, { 'x' => true }]),
        'b'       => condition_group('country' => 'US', '$not' => { '$savedGroup' => { 'id' => 'a' } }),
        'self'    => condition_group('country' => 'US', '$or' => [{ '$savedGroup' => { 'id' => 'self' } }, { 'x' => true }]),
        'outside' => condition_group('country' => 'US', '$savedGroup' => { 'id' => 'a' }),
        'plain'   => condition_group('country' => 'US', 'x' => true)
      }
      rules = %w[a self outside plain].map { |id| { 'condition' => { '$savedGroup' => { 'id' => id } }, 'force' => id } }
      payload = { 'features' => { 'f' => { 'defaultValue' => '', 'rules' => rules } }, 'savedGroups' => saved_groups }

      result = Growthbook.reduce_payload(payload, attributes: { country: 'US' })

      %w[a b self].each { |id| expect(result['savedGroups'][id]).to eq(saved_groups[id]) }
      # Not on a cycle, but it references one, so pruning can't decide it either
      expect(result['savedGroups']['outside']).to eq(saved_groups['outside'])
      expect(result['savedGroups']['plain']['condition']).to eq({ 'x' => true })
    end
  end
end
