# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'
require 'open3'
require 'rbconfig'

describe Growthbook::Context do
  describe 'feature helper methods' do
    it 'can evaluate a feature after loading the public SDK entrypoint' do
      script = <<~RUBY
        require 'growthbook'
        gb = Growthbook::Context.new(features: { feature: { defaultValue: true } })
        exit(gb.eval_feature(:feature).value == true ? 0 : 1)
      RUBY

      _stdout, _stderr, status = Open3.capture3(
        RbConfig.ruby,
        '-Ilib',
        '-e',
        script,
        chdir: File.expand_path('../..', __dir__)
      )

      expect(status).to be_success
    end

    gb = described_class.new(
      features: {
        feature1: {
          defaultValue: 1
        },
        feature2: {
          defaultValue: 0
        },
        feature3: {
          defaultValue: true
        },
        feature4: {
          defaultValue: false
        },
        feature5: {}
      }
    )

    it '.on?' do
      expect(gb.on?(:feature1)).to be(true)
      expect(gb.on?(:feature2)).to be(false)
      expect(gb.on?(:feature3)).to be(true)
      expect(gb.on?(:feature4)).to be(false)
      expect(gb.on?(:feature5)).to be(false)
    end

    it '.off?' do
      expect(gb.off?(:feature1)).to be(false)
      expect(gb.off?(:feature2)).to be(true)
      expect(gb.off?(:feature3)).to be(false)
      expect(gb.off?(:feature4)).to be(true)
      expect(gb.off?(:feature5)).to be(true)
    end

    it '.feature_value' do
      expect(gb.feature_value(:feature1)).to eq(1)
      expect(gb.feature_value(:feature2)).to eq(0)
      expect(gb.feature_value(:feature3)).to be(true)
      expect(gb.feature_value(:feature4)).to be(false)
      expect(gb.feature_value(:feature5)).to be_nil
    end
  end

  describe 'forced feature values' do
    it 'uses forced values' do
      gb = described_class.new(
        features: {
          feature: {
            defaultValue: 'a'
          },
          feature2: {
            defaultValue: true
          }
        }
      )

      gb.forced_features = {
        feature: 'b',
        another: 2
      }

      expect(gb.feature_value(:feature)).to eq('b')
      expect(gb.feature_value(:feature2)).to be(true)
      expect(gb.feature_value(:another)).to eq(2)
      expect(gb.feature_value(:unknown)).to be_nil
    end
  end

  describe 'malformed conditions' do
    it 'skips a rule whose condition raises instead of raising' do
      gb = described_class.new(
        attributes: { id: '1' },
        features: {
          feature: {
            defaultValue: 'default',
            rules: [
              { condition: { '$not' => nil }, force: 'malformed' },
              { condition: { 'id' => '1' }, force: 'next rule' }
            ]
          }
        }
      )

      expect(gb.feature_value(:feature)).to eq('next rule')
    end
  end

  describe 'feature usage callback' do
    let(:on_feature_usage) { double }

    before do
      allow(on_feature_usage).to receive(:on_feature_usage)
    end

    it 'is called when a feature value is evaluated' do
      gb = described_class.new(
        attributes: {
          id: '123'
        },
        features: {
          feature1: {
            defaultValue: 1,
            rules: [
              {
                variations: [2, 3]
              }
            ]
          },
          feature2: {
            defaultValue: 0,
            rules: [
              {
                variations: [4, 5]
              }
            ]
          }
        },
        on_feature_usage: on_feature_usage
      )

      gb.on?(:feature1)

      expect(on_feature_usage).to have_received(:on_feature_usage).with(
        'feature1',
        an_instance_of(Growthbook::FeatureResult)
      ) do |_key, feature_result|
        expect(feature_result.to_json).to eq(
          { 'on'               => true,
            'off'              => false,
            'value'            => 2,
            'source'           => 'experiment',
            'ruleId'           => '',
            'experiment'       => {
              'key'        => 'feature1',
              'variations' => [2, 3]
            },
            'experimentResult' => {
              'inExperiment'     => true,
              'variationId'      => 0,
              'value'            => 2,
              'hashUsed'         => true,
              'hashAttribute'    => 'id',
              'hashValue'        => '123',
              'featureId'        => 'feature1',
              'stickyBucketUsed' => false,
              'key'              => '0',
              'bucket'           => 0.154
            } }
        )
      end
    end
  end

  describe 'tracking' do
    let(:impression_listener) { double }

    before do
      allow(impression_listener).to receive(:on_experiment_viewed)
    end

    it 'queues up impressions' do
      gb = described_class.new(
        attributes: {
          id: '123'
        },
        features: {
          feature1: {
            defaultValue: 1,
            rules: [
              {
                variations: [2, 3]
              }
            ]
          },
          feature2: {
            defaultValue: 0,
            rules: [
              {
                variations: [4, 5]
              }
            ]
          }
        },
        listener: impression_listener
      )

      expect(gb.impressions).to eq({})

      gb.on? :feature1

      expect(gb.impressions['feature1'].to_json).to eq(
        {
          'bucket'           => 0.154,
          'key'              => '0',
          'featureId'        => 'feature1',
          'hashAttribute'    => 'id',
          'hashValue'        => '123',
          'inExperiment'     => true,
          'hashUsed'         => true,
          'stickyBucketUsed' => false,
          'value'            => 2,
          'variationId'      => 0
        }
      )
      expect(impression_listener).to have_received(:on_experiment_viewed).with(
        an_instance_of(Growthbook::InlineExperiment),
        an_instance_of(Growthbook::InlineExperimentResult)
      ) do |exp, res|
        expect(exp.to_json).to eq({ 'key' => 'feature1', 'variations' => [2, 3] })
        expect(res.to_json).to eq(
          {
            'bucket'           => 0.154,
            'key'              => '0',
            'featureId'        => 'feature1',
            'hashAttribute'    => 'id',
            'hashValue'        => '123',
            'inExperiment'     => true,
            'hashUsed'         => true,
            'stickyBucketUsed' => false,
            'value'            => 2,
            'variationId'      => 0
          }
        )
      end
    end
  end

  describe 'encrypted features' do
    context 'when provided an encryption key' do
      # uses "Valid feature" test
      subject(:context) do
        described_class.new(
          encrypted_features: 'm5ylFM6ndyOJA2OPadubkw==.Uu7ViqgKEt/dWvCyhI46q088PkAEJbnXKf3KPZjf9IEQQ+A8fojNoxw4wIbPX3aj',
          decryption_key: 'Zvwv/+uhpFDznZ6SX28Yjg==',
          attributes: {}
        )
      end

      it 'decrypts the payload' do
        expect(context.features['feature'].to_json['defaultValue']).to be(true)
      end

      context 'when decryption fails' do
        # uses "Broken JSON" test
        subject(:context) do
          described_class.new(
            encrypted_features: 'SVZIM2oKD1JoHNIeeoW3Uw==.AGbRiGAHf2f6/ziVr9UTIy+bVFmVli6+bHZ2jnCm9N991ITv1ROvOEjxjLSmgEpv',
            decryption_key: 'UQD0Qqw7fM1bhfKKPH8TGw==',
            attributes: {}
          )
        end

        it 'ignores setting the features' do
          expect(context.features).to eq({})
        end
      end
    end

    context 'when not provided an encryption key' do
      subject(:context) do
        described_class.new(
          features: payload,
          attributes: {}
        )
      end

      let(:payload) do
        {
          banner_text: {
            defaultValue: 'Welcome to Acme Donuts!',
            rules: [
              {
                condition: {
                  country: 'france'
                },
                force: 'Bienvenue au Beignets Acme !'
              },
              {
                condition: {
                  country: 'spain'
                },
                force: '¡Bienvenidos y bienvenidas a Donas Acme!'
              }
            ]
          }
        }
      end

      it 'uses the features hash as is' do
        expect(context.features['banner_text'].to_json['defaultValue']).to eq('Welcome to Acme Donuts!')
        expect(context.features['banner_text'].rules.first.force).to eq('Bienvenue au Beignets Acme !')
        expect(context.features['banner_text'].rules.last.force).to eq('¡Bienvenidos y bienvenidas a Donas Acme!')
      end
    end
  end

  describe 'hash attribute values' do
    let(:experiment) { Growthbook::InlineExperiment.new(key: 'my-test', variations: [0, 1], fallback_attribute: 'deviceId') }

    [true, false, 0, 0.0, '', nil, [], ['1'], {}, { 'a' => 1 }, Float::INFINITY].each do |id|
      it "treats #{id.inspect} as missing and uses the fallback attribute" do
        attributes = { 'id' => id, 'deviceId' => 'd1' }

        # Without sticky bucketing, experiments ignore the fallback attribute
        result = described_class.new(attributes: attributes).run(experiment)
        expect([result.in_experiment?, result.hash_used?]).to eq([false, false])

        gb = described_class.new(attributes: attributes, sticky_bucket_service: Growthbook::InMemoryStickyBucketService.new)
        result = gb.run(experiment)
        expect([result.in_experiment?, result.hash_attribute, result.hash_value]).to eq([true, 'deviceId', 'd1'])

        # Rollouts always use the rule's fallback attribute
        features = { 'f' => { 'defaultValue' => 'off', 'rules' => [{ 'force' => 'on', 'coverage' => 1, 'fallbackAttribute' => 'deviceId' }] } }
        expect(described_class.new(attributes: attributes, features: features).eval_feature('f').source).to eq('force')
        expect(described_class.new(attributes: { 'id' => id }, features: features).eval_feature('f').source).to eq('defaultValue')
      end
    end

    it 'hashes numbers like JS String()' do
      bucket = ->(id) { described_class.new(attributes: { 'id' => id }).run(Growthbook::InlineExperiment.new(key: 'k', variations: [0, 1])).bucket }
      expect(bucket.call(1.0)).to eq(bucket.call('1'))
      expect(bucket.call(1)).to eq(bucket.call('1'))
      expect(bucket.call(1.5)).to eq(bucket.call('1.5'))
    end

    it 'filters out users without a hash value' do
      experiment = Growthbook::InlineExperiment.new(
        key: 'k', variations: [0, 1], filters: [{ 'attribute' => 'company', 'seed' => 's', 'ranges' => [[0, 1]] }]
      )
      expect(described_class.new(attributes: { 'id' => '1' }).run(experiment).in_experiment?).to be(false)
    end
  end

  describe 'feature on and off' do
    { [] => true, {} => true, 'off' => true, '0' => true, 0 => false, 0.0 => false, '' => false, false => false, nil => false }.each do |value, on|
      it "is #{on ? 'on' : 'off'} for #{value.inspect}, like JS truthiness" do
        result = described_class.new(features: { 'f' => { 'defaultValue' => value } }).eval_feature('f')
        expect([result.on, result.off]).to eq([on, !on])
      end
    end
  end
end
