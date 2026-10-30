# frozen_string_literal: true

require 'spec_helper'
require 'growthbook'
require 'growthbook/redis_resolver'

RSpec.describe 'remote saved groups' do
  let(:saved_groups) do
    {
      'grp_vip'           => { 'type' => 'remote', 'attributeKey' => 'account_id' },
      'grp_vip:parent_id' => { 'type' => 'remote', 'attributeKey' => 'parent_id', 'valuesFrom' => 'grp_vip' },
      'grp_list'          => { 'type' => 'list', 'attributeKey' => 'id', 'values' => ['u_1'] }
    }
  end

  # GrowthBook guards "not in group" with $exists, as in the spec cases
  let(:not_in_vip) { { '$not' => { '$savedGroup' => { 'id' => 'grp_vip' } }, '__gb_remoteGroupIds' => { '$exists' => true } } }

  let(:features) do
    {
      'in_vip'     => { 'defaultValue' => false, 'rules' => [{ 'condition' => { '$savedGroup' => { 'id' => 'grp_vip' } }, 'force' => true }] },
      'not_in_vip' => { 'defaultValue' => false, 'rules' => [{ 'condition' => not_in_vip, 'force' => true }] }
    }
  end

  def context(**options)
    Growthbook::Context.new({ features: features, saved_groups: saved_groups, attributes: { 'account_id' => 'a1' } }.merge(options))
  end

  before { Growthbook::RemoteSavedGroups.instance_variable_set(:@warned_missing_ids, false) }

  describe 'Context#remote_group_ids' do
    it 'matches the groups it lists' do
      gb = context(remote_group_ids: ['grp_vip'])
      expect(gb.on?('in_vip')).to be(true)
      expect(gb.on?('not_in_vip')).to be(false)
    end

    it 'takes the remoteGroupIds option too' do
      expect(context(remoteGroupIds: ['grp_vip']).on?('in_vip')).to be(true)
    end

    it 'fails every rule using a remote group while unresolved, "not in group" included' do
      gb = context
      expect(gb.remote_group_ids).to be_nil
      expect(gb.on?('in_vip')).to be(false)
      expect(gb.on?('not_in_vip')).to be(false)
    end

    it 'treats an empty list as in no group' do
      gb = context(remote_group_ids: [])
      expect(gb.on?('in_vip')).to be(false)
      expect(gb.on?('not_in_vip')).to be(true)
    end

    it 'wins over the __gb_remoteGroupIds attribute without changing the attributes' do
      attributes = { 'account_id' => 'a1', '__gb_remoteGroupIds' => ['grp_vip'] }
      gb = context(attributes: attributes)
      expect(gb.on?('in_vip')).to be(true)

      gb.remote_group_ids = []
      expect(gb.on?('in_vip')).to be(false)
      expect(gb.attributes).to eq(attributes)
      expect(attributes).to eq({ 'account_id' => 'a1', '__gb_remoteGroupIds' => ['grp_vip'] })
    end

    it 'keeps applying when the attributes change' do
      gb = context(remote_group_ids: ['grp_vip'])
      gb.attributes = { 'account_id' => 'a2' }
      expect(gb.on?('in_vip')).to be(true)
    end

    it 'leaves $inGroup and $notInGroup on a remote group undecided, so they fail' do
      attributes = { 'account_id' => 'a1', '__gb_remoteGroupIds' => ['grp_vip'] }
      expect(Growthbook::Conditions.eval_condition(attributes, { 'account_id' => { '$inGroup' => 'grp_vip' } }, saved_groups)).to be(false)
      expect(Growthbook::Conditions.eval_condition(attributes, { 'account_id' => { '$notInGroup' => 'grp_vip' } }, saved_groups)).to be(false)
    end
  end

  describe 'the missing ids warning' do
    it 'is logged once, without attribute values' do
      gb = context(attributes: { 'account_id' => 'secret-account' })
      expect { gb.on?('in_vip') }.to output(/no remote group ids/).to_stderr
      expect { gb.on?('in_vip') }.not_to output.to_stderr
      expect { context.run(Growthbook::InlineExperiment.new(key: 'e', variations: [0, 1])) }.not_to output.to_stderr
    end

    it 'does not mention attribute values' do
      expect { context(attributes: { 'account_id' => 'secret-account' }).on?('in_vip') }.not_to output(/secret-account/).to_stderr
    end

    it 'is not logged when the ids are set, the attribute is, or the payload has no remote groups' do
      expect { context(remote_group_ids: []).on?('in_vip') }.not_to output.to_stderr
      expect { context(attributes: { '__gb_remoteGroupIds' => [] }).on?('in_vip') }.not_to output.to_stderr
      expect { context(saved_groups: { 'grp_list' => saved_groups['grp_list'] }).on?('in_vip') }.not_to output.to_stderr
    end
  end

  describe 'Context#add_remote_saved_groups' do
    it 'sets the ids the resolver returns, passing only the attributes remote groups use' do
      calls = []
      resolver = lambda do |attributes, groups|
        calls << [attributes, groups]
        ['grp_vip']
      end
      gb = context(attributes: { 'account_id' => 'a1', 'email' => 'user@example.test', 'id' => 'u_1' })

      expect(gb.add_remote_saved_groups(resolver)).to be(gb)
      expect(gb.remote_group_ids).to eq(['grp_vip'])
      expect(gb.on?('in_vip')).to be(true)
      expect(calls).to eq(
        [
          [
            { 'account_id' => 'a1' },
            [
              { 'id' => 'grp_vip', 'attributeKey' => 'account_id' },
              { 'id' => 'grp_vip:parent_id', 'attributeKey' => 'parent_id', 'valuesFrom' => 'grp_vip' }
            ]
          ]
        ]
      )
    end

    it 'reads a dot-separated attributeKey as a path' do
      received = nil
      gb = context(
        attributes: { 'company' => { 'id' => 'c1' } },
        saved_groups: { 'grp_co' => { 'type' => 'remote', 'attributeKey' => 'company.id' } }
      )
      gb.add_remote_saved_groups(->(attributes, _groups) { (received = attributes) && [] })
      expect(received).to eq({ 'company.id' => 'c1' })
    end

    it 'leaves the ids unset without calling the resolver when the payload has no remote groups' do
      gb = context(saved_groups: { 'grp_list' => saved_groups['grp_list'] })
      gb.add_remote_saved_groups(->(*) { raise 'not called' })
      expect(gb.remote_group_ids).to be_nil
    end

    it 'leaves the context unchanged when the resolver raises, logging only the error class' do
      gb = context(remote_group_ids: ['grp_old'], attributes: { 'account_id' => 'secret-account' })
      resolver = ->(*) { raise ArgumentError, 'gb:member:account_id:secret-account' }
      expect { gb.add_remote_saved_groups(resolver) }.to output(/ArgumentError/).to_stderr
      expect { gb.add_remote_saved_groups(resolver) }.not_to output(/secret-account/).to_stderr
      expect(gb.remote_group_ids).to eq(['grp_old'])
    end

    it 'leaves the context unchanged when the resolver does not return an array' do
      gb = context
      expect { gb.add_remote_saved_groups(->(*) { 'grp_vip' }) }.to output(/TypeError/).to_stderr
      expect(gb.remote_group_ids).to be_nil
    end

    it 'looks up again when the saved groups change during the lookup' do
      new_groups = saved_groups.merge('grp_new' => { 'type' => 'remote', 'attributeKey' => 'account_id' })
      gb = context
      seen = []
      resolver = lambda do |_attributes, groups|
        seen << groups.map { |g| g['id'] }
        gb.saved_groups = new_groups if seen.length == 1
        seen.length == 1 ? ['grp_vip'] : %w[grp_vip grp_new]
      end

      gb.add_remote_saved_groups(resolver)
      expect(seen).to eq([%w[grp_vip grp_vip:parent_id], %w[grp_vip grp_vip:parent_id grp_new]])
      expect(gb.remote_group_ids).to eq(%w[grp_vip grp_new])
    end

    it 'leaves the ids unset when the new saved groups have no remote groups' do
      gb = context
      gb.add_remote_saved_groups(
        lambda do |_attributes, _groups|
          gb.saved_groups = {}
          ['grp_vip']
        end
      )
      expect(gb.remote_group_ids).to be_nil
    end
  end

  describe 'pruning' do
    it 'leaves a remote group undecided while the ids are unknown' do
      condition = { '$savedGroup' => { 'id' => 'grp_vip' } }
      expect(Growthbook.prune_condition({ 'account_id' => 'a1' }, condition, saved_groups)).to eq(condition)
      expect(Growthbook.prune_condition({ '__gb_remoteGroupIds' => ['grp_vip'] }, condition, saved_groups)).to be(true)
      expect(Growthbook.prune_condition({ '__gb_remoteGroupIds' => [] }, condition, saved_groups)).to be(false)
    end

    it 'decides a reference with another attribute, which needs a derived group' do
      condition = { '$savedGroup' => { 'id' => 'grp_vip', 'attributeKey' => 'parent_id' } }
      expect(Growthbook.prune_condition({}, condition, saved_groups)).to be(false)
    end

    it 'keeps the remote groups a reduced payload uses' do
      payload = { 'features' => features, 'savedGroups' => saved_groups }
      reduced = Growthbook.reduce_payload(payload, attributes: { 'account_id' => 'a1' })
      expect(reduced['savedGroups']).to eq({ 'grp_vip' => saved_groups['grp_vip'] })
      expect(reduced['features']['in_vip']['rules'].first['condition']).to eq({ '$savedGroup' => { 'id' => 'grp_vip' } })
    end
  end

  describe Growthbook::RedisResolver do
    # Records each SMEMBERS key
    let(:redis) do
      Class.new do
        attr_reader :keys

        def initialize(sets = {})
          @sets = sets
          @keys = []
        end

        def smembers(key)
          @keys << key
          @sets.fetch(key, [])
        end
      end
    end

    let(:groups) { Growthbook::RemoteSavedGroups.groups(saved_groups) }

    it 'looks up each attribute value in its group' do
      client = redis.new('gb:member:account_id:a1' => %w[grp_vip grp_other])
      expect(described_class.new(client).call({ 'account_id' => 'a1' }, groups)).to eq(['grp_vip'])
      expect(client.keys).to eq(['gb:member:account_id:a1'])
    end

    it "checks a derived group's attribute in its source group's sets" do
      client = redis.new('gb:member:account_id:p1' => ['grp_vip'])
      ids = described_class.new(client).call({ 'account_id' => 'a1', 'parent_id' => 'p1' }, groups)
      expect(ids).to eq(['grp_vip:parent_id'])
    end

    it 'skips a derived group whose source group is missing' do
      client = redis.new('gb:member:parent_id:p1' => ['grp_vip:parent_id'])
      ids = described_class.new(client).call({ 'parent_id' => 'p1' }, [groups[1]])
      expect(ids).to eq([])
      expect(client.keys).to eq([])
    end

    it 'only matches the id it expects, so keys colliding on ":" stay apart' do
      colliding = Growthbook::RemoteSavedGroups.groups(
        'grp_a'  => { 'type' => 'remote', 'attributeKey' => 'a:b' },
        'grp_ab' => { 'type' => 'remote', 'attributeKey' => 'a' }
      )
      # `a:b` + `c` and `a` + `b:c` both read gb:member:a:b:c
      client = redis.new('gb:member:a:b:c' => ['grp_a'])
      ids = described_class.new(client).call({ 'a:b' => 'c', 'a' => 'b:c' }, colliding)
      expect(ids).to eq(['grp_a'])
      expect(client.keys).to eq(['gb:member:a:b:c'])
    end

    it 'looks up each item of an array, once per key' do
      client = redis.new('gb:member:account_id:a2' => ['grp_vip'])
      ids = described_class.new(client).call({ 'account_id' => %w[a1 a2 a1] }, [groups[0]])
      expect(ids).to eq(['grp_vip'])
      expect(client.keys).to eq(%w[gb:member:account_id:a1 gb:member:account_id:a2])
    end

    it 'formats numbers like JS String() and skips other values' do
      client = redis.new
      described_class.new(client).call({ 'account_id' => [1, 2.0, 1.5, 1e21, Float::NAN, Float::INFINITY, true, nil, { 'a' => 1 }] }, [groups[0]])
      expect(client.keys).to eq(%w[gb:member:account_id:1 gb:member:account_id:2 gb:member:account_id:1.5 gb:member:account_id:1e+21])
    end

    it 'works end to end through Context#add_remote_saved_groups' do
      client = redis.new('gb:member:account_id:a1' => ['grp_vip'])
      gb = context.add_remote_saved_groups(described_class.new(client))
      expect(gb.remote_group_ids).to eq(['grp_vip'])
      expect(gb.on?('in_vip')).to be(true)
    end
  end
end
