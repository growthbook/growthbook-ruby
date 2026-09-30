# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

RSpec.describe 'contextual bandit evaluation' do
  describe 'Growthbook::Context' do
    let(:features) do
      {
        'bandit-feature' => {
          'defaultValue' => 'default',
          'rules'        => [
            {
              'key'                  => 'bandit-exp',
              'seed'                 => 'bandit-exp',
              'hashAttribute'        => 'id',
              'hashVersion'          => 2,
              'coverage'             => 1,
              'contextualVariations' => %w[control treatment],
              'weights'              => [0.5, 0.5],
              'meta'                 => [{ 'key' => '0' }, { 'key' => '1' }],
              'contextualBanditRef'  => 'cb-bandit'
            }
          ]
        }
      }
    end
    let(:bandits) do
      {
        'cb-bandit' => {
          'banditVersion' => 7,
          'contexts'      => [{ 'leafId' => 1, 'condition' => {}, 'weights' => [1, 0] }]
        }
      }
    end

    it 'accepts definitions as an option' do
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' }, contextual_bandits: bandits)

      expect(gb.contextual_bandits['cb-bandit']).to be_a(Growthbook::ContextualBanditDefinition)
      expect(gb.feature_value('bandit-feature')).to eq('control')
    end

    it 'accepts the camelCase option name used by the payload' do
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' }, contextualBandits: bandits)

      expect(gb.contextual_bandits.keys).to eq(['cb-bandit'])
    end

    it 'can be replaced after construction' do
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' })
      expect(gb.feature_value('bandit-feature')).to eq('treatment')

      gb.contextual_bandits = bandits

      expect(gb.feature_value('bandit-feature')).to eq('control')
    end

    it 'clears the definitions when given nil' do
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' }, contextual_bandits: bandits)

      gb.contextual_bandits = nil

      expect(gb.contextual_bandits).to eq({})
    end

    it 'reports the routing on the experiment result' do
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' }, contextual_bandits: bandits)
      result = gb.eval_feature('bandit-feature').experiment_result

      expect(result.leaf_id).to eq(1)
      expect(result.variation_weights).to eq([1, 0])
      expect(result.bandit_version).to eq(7)
    end

    it 'reports nothing when the definition is missing' do
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' })
      result = gb.eval_feature('bandit-feature').experiment_result

      expect(result.leaf_id).to be_nil
      expect(result.variation_weights).to be_nil
      expect(result.bandit_version).to be_nil
    end

    it 'falls back to the fallback leaf when a leaf condition throws' do
      allow(Growthbook::Conditions).to receive(:eval_condition).and_raise(StandardError, 'boom')
      gb = Growthbook::Context.new(features: features, attributes: { id: '1' }, contextual_bandits: bandits)

      result = gb.eval_feature('bandit-feature').experiment_result

      expect(result.leaf_id).to eq(-1)
      expect(result.variation_weights).to eq([0.5, 0.5])
    end

    it 'derives sticky bucket attributes from a bandit rule too' do
      bandit_rule = features['bandit-feature']['rules'].first.merge('hashAttribute' => 'device_id')
      gb = Growthbook::Context.new(
        features: { 'bandit-feature' => { 'defaultValue' => 'default', 'rules' => [bandit_rule] } },
        attributes: { 'device_id' => 'device-1' },
        contextual_bandits: bandits,
        sticky_bucket_service: Growthbook::InMemoryStickyBucketService.new
      )

      expect(gb.sticky_bucket_attributes).to eq('device_id' => 'device-1')
    end

    it 'does not treat a bandit rule as a force rule' do
      rule = Growthbook::FeatureRule.new(features['bandit-feature']['rules'].first)

      expect(rule.experiment?).to be(true)
      expect(rule.force?).to be(false)
    end
  end

  describe 'Growthbook::FeatureRepository' do
    let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-bandits' }
    let(:bandits) do
      { 'cb-bandit' => { 'banditVersion' => 7, 'contexts' => [{ 'leafId' => 1, 'weights' => [1, 0] }] } }
    end

    it 'parses contextualBandits from the payload' do
      stub_request(:get, endpoint).to_return(
        status: 200,
        body: JSON.generate('features' => {}, 'contextualBandits' => bandits)
      )
      repo = Growthbook::FeatureRepository.new(endpoint: endpoint, decryption_key: nil)
      repo.fetch

      expect(repo.contextual_bandits_json).to eq(bandits)
    end

    it 'defaults to an empty hash when the payload has none' do
      stub_request(:get, endpoint).to_return(status: 200, body: JSON.generate('features' => {}))
      repo = Growthbook::FeatureRepository.new(endpoint: endpoint, decryption_key: nil)
      repo.fetch

      expect(repo.contextual_bandits_json).to eq({})
    end

    it 'decrypts encryptedContextualBandits' do
      key = 'Ns04T5n9+59rl2x3SlNHtQ=='
      stub_request(:get, endpoint).to_return(
        status: 200,
        body: JSON.generate(
          'encryptedFeatures'          => encrypt('{}', key),
          'encryptedContextualBandits' => encrypt(JSON.generate(bandits), key)
        )
      )
      repo = Growthbook::FeatureRepository.new(endpoint: endpoint, decryption_key: key)
      repo.fetch

      expect(repo.contextual_bandits_json).to eq(bandits)
    end

    # Mirror of Growthbook::DecryptionUtil.decrypt, which has no encrypting counterpart
    def encrypt(plaintext, key)
      cipher = OpenSSL::Cipher.new('aes-128-cbc')
      cipher.encrypt
      cipher.key = Base64.strict_decode64(key)
      iv = cipher.random_iv

      "#{Base64.strict_encode64(iv)}.#{Base64.strict_encode64(cipher.update(plaintext) + cipher.final)}"
    end
  end
end
