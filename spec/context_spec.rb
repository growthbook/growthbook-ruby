# frozen_string_literal: true

require 'spec_helper'
require 'growthbook'
require 'json'

describe 'context' do
  describe 'feature helper methods' do
    gb = Growthbook::Context.new(
      features: {
        feature1: {
          defaultValue: 1
        },
        feature2: {
          defaultValue: 0
        }
      }
    )

    it '.on?' do
      expect(gb.on?(:feature1)).to be(true)
      expect(gb.on?(:feature2)).to be(false)
    end

    it '.off?' do
      expect(gb.off?(:feature1)).to be(false)
      expect(gb.off?(:feature2)).to be(true)
    end

    it '.feature_value' do
      expect(gb.feature_value(:feature1)).to eq(1)
      expect(gb.feature_value(:feature2)).to eq(0)
    end
  end

  describe 'forced feature values' do
    it 'uses forced values' do
      gb = Growthbook::Context.new(
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

  describe 'tracking' do
    let(:impression_listener) { double }

    before do
      allow(impression_listener).to receive(:on_experiment_viewed)
    end

    it 'queues up impressions' do
      gb = Growthbook::Context.new(
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
          'bucket'        => 0.154,
          'key'           => '0',
          'featureId'     => 'feature1',
          'hashAttribute' => 'id',
          'hashValue'     => '123',
          'inExperiment'  => true,
          'hashUsed'      => true,
          'value'         => 2,
          'variationId'   => 0
        }
      )
      expect(impression_listener).to have_received(:on_experiment_viewed).with(
        an_instance_of(Growthbook::InlineExperiment),
        an_instance_of(Growthbook::InlineExperimentResult)
      ) do |exp, res|
        expect(exp.to_json).to eq({ 'key' => 'feature1', 'variations' => [2, 3] })
        expect(res.to_json).to eq(
          {
            'bucket'        => 0.154,
            'key'           => '0',
            'featureId'     => 'feature1',
            'hashAttribute' => 'id',
            'hashValue'     => '123',
            'inExperiment'  => true,
            'hashUsed'      => true,
            'value'         => 2,
            'variationId'   => 0
          }
        )
      end
    end
  end

  describe 'encrypted features' do
    context 'when provided an encryption key' do
      # uses "Valid feature" test
      subject(:context) do
        Growthbook::Context.new(
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
          Growthbook::Context.new(
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
        Growthbook::Context.new(
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
end
