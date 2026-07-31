# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

RSpec.describe Growthbook::RemoteEvalRepository do
  subject(:repository) do
    described_class.new(
      api_host: api_host,
      client_key: 'sdk-abc123',
      cache: cache
    )
  end

  let(:api_host) { 'https://gb-proxy.example.com' }
  let(:cache) { nil }
  let(:endpoint) { 'https://gb-proxy.example.com/api/eval/sdk-abc123' }
  let(:features) do
    {
      'banner_text' => { 'defaultValue' => 'Bienvenue' }
    }
  end
  let(:response_body) { JSON.generate('features' => features, 'savedGroups' => { 'beta' => %w[1 2] }) }

  describe '.initialize' do
    its(:endpoint) { is_expected.to eq(endpoint) }
    its(:features_json) { is_expected.to eq({}) }
    its(:saved_groups_json) { is_expected.to eq({}) }

    it 'strips trailing slashes from the api host' do
      repo = described_class.new(api_host: 'https://gb-proxy.example.com/', client_key: 'sdk-abc123')

      expect(repo.endpoint).to eq(endpoint)
    end

    it 'rejects a GrowthBook Cloud host' do
      expect { described_class.new(api_host: 'https://cdn.growthbook.io', client_key: 'sdk-abc123') }
        .to raise_error(ArgumentError, /GrowthBook Cloud/)
    end

    it 'rejects a subdomain of GrowthBook Cloud' do
      expect { described_class.new(api_host: 'https://foo.growthbook.io', client_key: 'sdk-abc123') }
        .to raise_error(ArgumentError, /GrowthBook Cloud/)
    end

    it 'allows a self-hosted host that merely contains the cloud domain' do
      repo = described_class.new(api_host: 'https://growthbook.io.example.com', client_key: 'sdk-abc123')

      expect(repo.endpoint).to eq('https://growthbook.io.example.com/api/eval/sdk-abc123')
    end

    it 'requires a client key' do
      expect { described_class.new(api_host: api_host, client_key: '') }
        .to raise_error(ArgumentError, /client_key/)
    end

    it 'requires an api host' do
      expect { described_class.new(api_host: nil, client_key: 'sdk-abc123') }
        .to raise_error(ArgumentError, /api_host/)
    end
  end

  describe '#fetch' do
    it 'POSTs the evaluation context and returns the evaluated features' do
      stub = stub_request(:post, endpoint)
               .with(
                 headers: { 'Content-Type' => 'application/json' },
                 body: {
                   'attributes'       => { 'id' => '1' },
                   'forcedFeatures'   => [%w[dark_mode true]],
                   'forcedVariations' => { 'exp' => 1 },
                   'url'              => 'https://example.com/pricing'
                 }
               )
               .to_return(status: 200, body: response_body)

      result = repository.fetch(
        attributes: { id: '1' },
        forced_variations: { 'exp' => 1 },
        forced_features: { 'dark_mode' => 'true' },
        url: 'https://example.com/pricing'
      )

      expect(stub).to have_been_requested
      expect(result['features']).to eq(features)
      expect(result['savedGroups']).to eq('beta' => %w[1 2])
    end

    it 'exposes the last successful response' do
      stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'id' => '1' })

      expect(repository.features_json).to eq(features)
      expect(repository.saved_groups_json).to eq('beta' => %w[1 2])
    end

    it 'sends empty objects when the context is empty' do
      stub = stub_request(:post, endpoint)
               .with(body: { 'attributes' => {}, 'forcedFeatures' => [], 'forcedVariations' => {}, 'url' => '' })
               .to_return(status: 200, body: response_body)

      repository.fetch

      expect(stub).to have_been_requested
    end

    it 'returns nil on an error response' do
      stub_request(:post, endpoint).to_return(status: 500, body: 'nope')

      expect(repository.fetch(attributes: { 'id' => '1' })).to be_nil
    end

    it 'returns nil when the connection fails' do
      stub_request(:post, endpoint).to_timeout

      expect(repository.fetch(attributes: { 'id' => '1' })).to be_nil
    end

    it 'returns nil on an unparseable response' do
      stub_request(:post, endpoint).to_return(status: 200, body: 'not json')

      expect(repository.fetch(attributes: { 'id' => '1' })).to be_nil
    end

    it 'returns nil when the response has no features' do
      stub_request(:post, endpoint).to_return(status: 200, body: JSON.generate('savedGroups' => {}))

      expect(repository.fetch(attributes: { 'id' => '1' })).to be_nil
    end

    it 'defaults saved groups to an empty hash' do
      stub_request(:post, endpoint).to_return(status: 200, body: JSON.generate('features' => features))

      expect(repository.fetch(attributes: { 'id' => '1' })['savedGroups']).to eq({})
    end
  end

  describe '#fetch!' do
    it 'returns the evaluated features' do
      stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      expect(repository.fetch!(attributes: { 'id' => '1' })['features']).to eq(features)
    end

    it 'raises when the request fails' do
      stub_request(:post, endpoint).to_return(status: 500)

      expect { repository.fetch!(attributes: { 'id' => '1' }) }
        .to raise_error(described_class::RemoteEvalFetchError)
    end
  end

  describe 'caching' do
    let(:cache) { Growthbook::InMemoryRemoteEvalCache.new }

    it 'serves a repeated context from the cache' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'id' => '1' })
      result = repository.fetch(attributes: { 'id' => '1' })

      expect(stub).to have_been_requested.once
      expect(result['features']).to eq(features)
    end

    it 'refetches when an attribute changes' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'id' => '1' })
      repository.fetch(attributes: { 'id' => '2' })

      expect(stub).to have_been_requested.twice
    end

    it 'refetches when the forced variations change' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'id' => '1' })
      repository.fetch(attributes: { 'id' => '1' }, forced_variations: { 'exp' => 1 })

      expect(stub).to have_been_requested.twice
    end

    it 'ignores attribute order' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'id' => '1', 'country' => 'US' })
      repository.fetch(attributes: { 'country' => 'US', 'id' => '1' })

      expect(stub).to have_been_requested.once
    end

    it 'keys the cache on the contents of an array attribute' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'tags' => %w[a b] })
      repository.fetch(attributes: { 'tags' => %w[a b] })
      repository.fetch(attributes: { 'tags' => %w[b a] })

      expect(stub).to have_been_requested.twice
    end

    it 'ignores key order inside a nested attribute' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'company' => { 'id' => '1', 'plan' => 'pro' } })
      repository.fetch(attributes: { 'company' => { 'plan' => 'pro', 'id' => '1' } })

      expect(stub).to have_been_requested.once
    end

    it 'does not key the cache on forced features' do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      repository.fetch(attributes: { 'id' => '1' })
      repository.fetch(attributes: { 'id' => '1' }, forced_features: { 'dark_mode' => true })

      expect(stub).to have_been_requested.once
    end

    it 'falls back to a stale response when the endpoint fails' do
      stub_request(:post, endpoint).to_return(status: 200, body: response_body)
      repository.fetch(attributes: { 'id' => '1' })

      # Expire the cached entry without waiting for the TTL
      allow(Time).to receive(:now).and_return(Time.at(Time.now.to_i + 3600))
      stub_request(:post, endpoint).to_return(status: 500)

      expect(repository.fetch(attributes: { 'id' => '1' })['features']).to eq(features)
    end

    it 'does not cache a failed response' do
      stub_request(:post, endpoint).to_return(status: 500)
      repository.fetch(attributes: { 'id' => '1' })

      # The retry has to hit the endpoint again rather than serve the failure
      stub_request(:post, endpoint).to_return(status: 200, body: response_body)

      expect(repository.fetch(attributes: { 'id' => '1' })['features']).to eq(features)
      expect(a_request(:post, endpoint)).to have_been_made.twice
    end

    context 'with cache_key_attributes' do
      subject(:repository) do
        described_class.new(
          api_host: api_host,
          client_key: 'sdk-abc123',
          cache: cache,
          cache_key_attributes: ['id']
        )
      end

      it 'ignores attributes outside the key' do
        stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

        repository.fetch(attributes: { 'id' => '1', 'country' => 'US' })
        repository.fetch(attributes: { 'id' => '1', 'country' => 'FR' })

        expect(stub).to have_been_requested.once
      end

      it 'still refetches when an attribute in the key changes' do
        stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

        repository.fetch(attributes: { 'id' => '1', 'country' => 'US' })
        repository.fetch(attributes: { 'id' => '2', 'country' => 'US' })

        expect(stub).to have_been_requested.twice
      end
    end

    context 'when caching is disabled' do
      let(:cache) { nil }

      it 'sends a request every time' do
        stub = stub_request(:post, endpoint).to_return(status: 200, body: response_body)

        repository.fetch(attributes: { 'id' => '1' })
        repository.fetch(attributes: { 'id' => '1' })

        expect(stub).to have_been_requested.twice
      end
    end
  end
end
