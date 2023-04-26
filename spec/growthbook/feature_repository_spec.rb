# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

RSpec.describe Growthbook::FeatureRepository do
  describe '.initialize' do
    subject do
      described_class.new(
        endpoint: 'https://cdn.growthbook.io/api/features/key-abc123',
        decryption_key: nil
      )
    end

    its(:endpoint) { is_expected.to eq('https://cdn.growthbook.io/api/features/key-abc123') }
    its(:decryption_key) { is_expected.to be_nil }

    context 'when provided a decryption key' do
      subject do
        described_class.new(
          endpoint: 'https://cdn.growthbook.io/api/features/key-abc123',
          decryption_key: 'some-key'
        )
      end

      its(:endpoint) { is_expected.to eq('https://cdn.growthbook.io/api/features/key-abc123') }
      its(:decryption_key) { is_expected.to eq('some-key') }
    end
  end

  describe '#fetch' do
    context 'when not using a decryption key' do
      subject(:fetch_response) do
        described_class.new(
          endpoint: endpoint,
          decryption_key: nil
        ).fetch
      end

      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-acme-donuts' }
      let(:json_response) do
        <<~JSON
          {
            "status": 200,
            "features": {
              "banner_text": {
                "defaultValue": "Welcome to Acme Donuts!",
                "rules": [
                  {
                    "condition": { "country": "france" },
                    "force": "Bienvenue au Beignets Acme !"
                  },
                  {
                    "condition": { "country": "spain" },
                    "force": "¡Bienvenidos y bienvenidas a Donas Acme!"
                  }
                ]
              },
              "dark_mode": {
                "defaultValue": false,
                "rules": [
                  {
                    "condition": { "loggedIn": true },
                    "force": true,
                    "coverage": 0.5,
                    "hashAttribute": "id"
                  }
                ]
              },
              "donut_price": {
                "defaultValue": 2.5,
                "rules": [{ "condition": { "employee": true }, "force": 0 }]
              },
              "meal_overrides_gluten_free": {
                "defaultValue": {
                  "meal_type": "standard",
                  "dessert": "Strawberry Cheesecake"
                },
                "rules": [
                  {
                    "condition": {
                      "dietaryRestrictions": { "$elemMatch": { "$eq": "gluten_free" } }
                    },
                    "force": { "meal_type": "gf", "dessert": "French Vanilla Ice Cream" }
                  }
                ]
              }
            },
            "dateUpdated": "2023-04-03T07:35:12.621Z"
          }
        JSON
      end

      before do
        stub_request(:get, endpoint)
          .to_return(status: 200, body: json_response, headers: {})
      end

      it 'returns parsed JSON from the response features' do
        expect(fetch_response['banner_text']['defaultValue']).to eq('Welcome to Acme Donuts!')
      end

      context 'when provided a misconfigured URL' do
        subject(:fetch_response) do
          described_class.new(
            endpoint: endpoint,
            decryption_key: nil
          ).fetch
        end

        let(:endpoint) { 'hello! this is not a URL' }

        it { is_expected.to be_nil }
      end

      context 'when the network request fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 500, body: '💥 Boom!', headers: {})
        end

        it { is_expected.to be_nil }
      end

      context 'when the parsing fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 200, body: '🤨 some unparsable response', headers: {})
        end

        it { is_expected.to be_nil }
      end
    end

    context 'when provided a decryption key' do
      subject(:fetch_response) do
        described_class.new(
          endpoint: endpoint,
          decryption_key: 'BhB1wORFmZLTDjbvstvS8w=='
        ).fetch
      end

      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-862b5mHcP9XPugqD' }
      let(:json_response) do
        <<~JSON
          {
            "status": 200,
            "features": {},
            "dateUpdated": "2023-04-03T16:09:00.800Z",
            "encryptedFeatures": "Utj/Xwn7YaTXX8vHosRFQg==.yYuNdFoTv1aebOyhC7lTUpNSUW9toE4nSTMATKaT3mGwrzUUMrGg/3uJ0edpxRdoZcAD778+eDBlT9+i/wc+eMzBTK9KkEWSZG/hljlZjRP8zVbfggm/yy1E87xsGl1JnSkQ+iRyMTsrdEvvo2AkoQqFbmEOvOklcYAIZTMaYsgCOi+9BRbI1s6HLpI/kCE4kcuhePY0b20oWrpDL++wDQ=="
          }
        JSON
      end

      before do
        stub_request(:get, endpoint)
          .to_return(status: 200, body: json_response, headers: {})
      end

      it 'returns decrypted parsed JSON from the response encryptedFeatures' do
        expect(fetch_response['greeting']['rules'][0]).to eq(
          {
            'condition' => { 'country' => 'france' },
            'force'     => 'bonjour'
          }
        )
      end

      context 'when the network request fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 500, body: '💥 Boom!', headers: {})
        end

        it { is_expected.to be_nil }
      end

      context 'when the parsing fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 200, body: '🤨 some unparsable response', headers: {})
        end

        it { is_expected.to be_nil }
      end

      context 'when the decryption fails' do
        let(:json_response) do
          <<~JSON
            {
              "status": 200,
              "features": {},
              "dateUpdated": "2023-04-03T16:09:00.800Z",
              "encryptedFeatures": "Utj/Xwn7YaTXX8vHosRFQg==.yYuNdFoTv1aebOyh_NOPE_NOPE_NOPE_4nSTMATKaT3mGwrzUUMrGg/3uJ0edpxRdoZcAD778+eDBlT9+i/wc+eMzBTK9KkEWSZG/hljlZjRP8zVbfggm/yy1E87xsGl1JnSkQ+iRyMTsrdEvvo2AkoQqFbmEOvOklcYAIZTMaYsgCOi+9BRbI1s6HLpI/kCE4kcuhePY0b20oWrpDL++wDQ=="
            }
          JSON
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe '#fetch!' do
    context 'when provided a misconfigured URL' do
      subject(:fetch_response) do
        described_class.new(
          endpoint: endpoint,
          decryption_key: nil
        ).fetch!
      end

      let(:endpoint) { 'hello! this is not a URL' }

      it 'raises a FeatureFetchError' do
        expect { fetch_response }.to raise_error Growthbook::FeatureRepository::FeatureFetchError
      end
    end

    context 'when not using a decryption key' do
      subject(:fetch_response) do
        described_class.new(
          endpoint: endpoint,
          decryption_key: nil
        ).fetch!
      end

      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-acme-donuts' }
      let(:json_response) do
        <<~JSON
          {
            "status": 200,
            "features": {
              "banner_text": {
                "defaultValue": "Welcome to Acme Donuts!",
                "rules": [
                  {
                    "condition": { "country": "france" },
                    "force": "Bienvenue au Beignets Acme !"
                  },
                  {
                    "condition": { "country": "spain" },
                    "force": "¡Bienvenidos y bienvenidas a Donas Acme!"
                  }
                ]
              },
              "dark_mode": {
                "defaultValue": false,
                "rules": [
                  {
                    "condition": { "loggedIn": true },
                    "force": true,
                    "coverage": 0.5,
                    "hashAttribute": "id"
                  }
                ]
              },
              "donut_price": {
                "defaultValue": 2.5,
                "rules": [{ "condition": { "employee": true }, "force": 0 }]
              },
              "meal_overrides_gluten_free": {
                "defaultValue": {
                  "meal_type": "standard",
                  "dessert": "Strawberry Cheesecake"
                },
                "rules": [
                  {
                    "condition": {
                      "dietaryRestrictions": { "$elemMatch": { "$eq": "gluten_free" } }
                    },
                    "force": { "meal_type": "gf", "dessert": "French Vanilla Ice Cream" }
                  }
                ]
              }
            },
            "dateUpdated": "2023-04-03T07:35:12.621Z"
          }
        JSON
      end

      before do
        stub_request(:get, endpoint)
          .to_return(status: 200, body: json_response, headers: {})
      end

      it 'returns parsed JSON from the response features' do
        expect(fetch_response['banner_text']['defaultValue']).to eq('Welcome to Acme Donuts!')
      end

      context 'when the network request fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 500, body: '💥 Boom!', headers: {})
        end

        it 'raises a FeatureFetchError' do
          expect { fetch_response }.to raise_error Growthbook::FeatureRepository::FeatureFetchError
        end
      end

      context 'when the parsing fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 200, body: '🤨 some unparsable response', headers: {})
        end

        it 'raises a FeatureParseError' do
          expect { fetch_response }.to raise_error Growthbook::FeatureRepository::FeatureParseError
        end
      end
    end

    context 'when provided a decryption key' do
      subject(:fetch_response) do
        described_class.new(
          endpoint: endpoint,
          decryption_key: 'BhB1wORFmZLTDjbvstvS8w=='
        ).fetch!
      end

      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-862b5mHcP9XPugqD' }
      let(:json_response) do
        <<~JSON
          {
            "status": 200,
            "features": {},
            "dateUpdated": "2023-04-03T16:09:00.800Z",
            "encryptedFeatures": "Utj/Xwn7YaTXX8vHosRFQg==.yYuNdFoTv1aebOyhC7lTUpNSUW9toE4nSTMATKaT3mGwrzUUMrGg/3uJ0edpxRdoZcAD778+eDBlT9+i/wc+eMzBTK9KkEWSZG/hljlZjRP8zVbfggm/yy1E87xsGl1JnSkQ+iRyMTsrdEvvo2AkoQqFbmEOvOklcYAIZTMaYsgCOi+9BRbI1s6HLpI/kCE4kcuhePY0b20oWrpDL++wDQ=="
          }
        JSON
      end

      before do
        stub_request(:get, endpoint)
          .to_return(status: 200, body: json_response, headers: {})
      end

      it 'returns decrypted parsed JSON from the response encryptedFeatures' do
        expect(fetch_response['greeting']['rules'][0]).to eq(
          {
            'condition' => { 'country' => 'france' },
            'force'     => 'bonjour'
          }
        )
      end

      context 'when the network request fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 500, body: '💥 Boom!', headers: {})
        end

        it 'raises a FeatureFetchError' do
          expect { fetch_response }.to raise_error Growthbook::FeatureRepository::FeatureFetchError
        end
      end

      context 'when the parsing fails' do
        before do
          stub_request(:get, endpoint)
            .to_return(status: 200, body: '🤨 some unparsable response', headers: {})
        end

        it 'raises a FeatureParseError' do
          expect { fetch_response }.to raise_error Growthbook::FeatureRepository::FeatureParseError
        end
      end

      context 'when the decryption fails' do
        let(:json_response) do
          <<~JSON
            {
              "status": 200,
              "features": {},
              "dateUpdated": "2023-04-03T16:09:00.800Z",
              "encryptedFeatures": "Utj/Xwn7YaTXX8vHosRFQg==.yYuNdFoTv1aebOyh_NOPE_NOPE_NOPE_4nSTMATKaT3mGwrzUUMrGg/3uJ0edpxRdoZcAD778+eDBlT9+i/wc+eMzBTK9KkEWSZG/hljlZjRP8zVbfggm/yy1E87xsGl1JnSkQ+iRyMTsrdEvvo2AkoQqFbmEOvOklcYAIZTMaYsgCOi+9BRbI1s6HLpI/kCE4kcuhePY0b20oWrpDL++wDQ=="
            }
          JSON
        end

        it 'raises a FeatureParseError' do
          expect { fetch_response }.to raise_error Growthbook::FeatureRepository::FeatureParseError
        end
      end
    end
  end
end
