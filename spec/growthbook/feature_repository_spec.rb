# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'
require 'socket'

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

  describe '#start_auto_refresh' do
    subject(:repo) { described_class.new(endpoint: endpoint, decryption_key: nil) }

    let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-abc123' }
    let(:stream_url) { 'https://cdn.growthbook.io/sub/sdk-abc123' }
    let(:updates) { [] }
    let(:on_update) { ->(features, _saved_groups) { updates << features } }

    # Polls until the block returns true or two seconds pass
    def wait_until
      deadline = Time.now + 2
      sleep 0.01 until yield || Time.now > deadline
    end

    def features_event
      "event: features\ndata: {\"features\":{\"banner\":{\"defaultValue\":1}}}\n\n"
    end

    def stub_features(body, sse: true)
      headers = sse ? { 'x-sse-support' => 'enabled' } : {}
      stub_request(:get, endpoint).to_return(status: 200, body: body, headers: headers)
    end

    after { repo.stop_auto_refresh }

    it 'does not start when the server does not support SSE' do
      stub_features('{"features":{}}', sse: false)
      repo.fetch

      expect do
        expect(repo.start_auto_refresh).to be(false)
      end.to output(/x-sse-support/).to_stderr
      expect(repo.auto_refreshing?).to be(false)
    end

    it 'applies the payload of a "features" event' do
      stub_features('{"features":{}}')
      stub_request(:get, stream_url).to_return(status: 200, body: features_event)
      repo.fetch

      expect(repo.start_auto_refresh(on_update: on_update)).to be(true)
      wait_until { updates.any? }

      expect(repo.features_json).to eq({ 'banner' => { 'defaultValue' => 1 } })
      expect(updates.first).to eq(repo.features_json)
    end

    it 'fetches again on a "features-updated" event' do
      stub_features('{"features":{}}')
      repo.fetch
      stub_features('{"features":{"banner":{"defaultValue":2}}}')
      stub_request(:get, stream_url).to_return(status: 200, body: "event: features-updated\n\n")

      repo.start_auto_refresh(on_update: on_update)
      wait_until { updates.any? }

      expect(repo.features_json).to eq({ 'banner' => { 'defaultValue' => 2 } })
    end

    it 'connects to a custom streaming host' do
      stub_features('{"features":{}}')
      stub_request(:get, 'https://stream.example.com/sub/sdk-abc123').to_return(status: 200, body: features_event)
      repo.fetch

      repo.start_auto_refresh(streaming_host: 'https://stream.example.com/', on_update: on_update)
      wait_until { updates.any? }

      expect(updates).not_to be_empty
    end

    context 'when the API sits behind a proxy path' do
      let(:endpoint) { 'https://proxy.example.com/gb/api/features/sdk-abc123' }
      let(:stream_url) { 'https://proxy.example.com/gb/sub/sdk-abc123' }

      it 'keeps the path prefix in the stream url' do
        stub_features('{"features":{}}')
        stub_request(:get, stream_url).to_return(status: 200, body: features_event)
        repo.fetch

        repo.start_auto_refresh(on_update: on_update)
        wait_until { updates.any? }

        expect(updates).not_to be_empty
      end
    end

    it 'fetches again after the stream reconnects' do
      # Reconnect at once instead of after 1-2 s
      allow(Growthbook::SSEClient).to receive(:new).and_wrap_original do |original, options|
        original.call(**options, reconnect_delay: 0.01, max_reconnect_delay: 0.05)
      end
      stub_features('{"features":{}}')
      repo.fetch
      stub_features('{"features":{"banner":{"defaultValue":3}}}')
      stub_request(:get, stream_url).to_return(status: 200, body: '')

      repo.start_auto_refresh(on_update: on_update)
      wait_until { updates.any? }

      expect(repo.features_json).to eq({ 'banner' => { 'defaultValue' => 3 } })
    end

    it 'accepts an endpoint with a trailing slash' do
      repo = described_class.new(endpoint: "#{endpoint}/", decryption_key: nil)

      expect(repo.send(:streaming_url, nil)).to eq(stream_url)
    end

    it 'rejects an endpoint it cannot turn into a stream url' do
      repo = described_class.new(endpoint: 'https://proxy.example.com/api/eval/sdk-abc123', decryption_key: nil)
      stub_request(:get, repo.endpoint).to_return(status: 200, body: '{"features":{}}', headers: { 'x-sse-support' => 'enabled' })
      repo.fetch

      expect { repo.start_auto_refresh }.to raise_error(ArgumentError, %r{api/features})
    end

    it 'stops streaming' do
      stub_features('{"features":{}}')
      stub_request(:get, stream_url).to_return(status: 200, body: '')
      repo.fetch
      repo.start_auto_refresh

      repo.stop_auto_refresh
      expect(repo.auto_refreshing?).to be(false)
    end
  end

  describe '#snapshot' do
    let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-snapshot' }
    let(:encrypted_features) do
      'Utj/Xwn7YaTXX8vHosRFQg==.yYuNdFoTv1aebOyhC7lTUpNSUW9toE4nSTMATKaT3mGwrzUUMrGg/3uJ0edpxRdoZcAD778+eDBlT9+i/wc+' \
        'eMzBTK9KkEWSZG/hljlZjRP8zVbfggm/yy1E87xsGl1JnSkQ+iRyMTsrdEvvo2AkoQqFbmEOvOklcYAIZTMaYsgCOi+9BRbI1s6HLpI/kCE4' \
        'kcuhePY0b20oWrpDL++wDQ=='
    end

    it 'returns the features and saved groups of the same payload' do
      repo = described_class.new(endpoint: endpoint, decryption_key: nil)
      stub_request(:get, endpoint)
        .to_return(status: 200, body: '{"features":{"f":{"defaultValue":1}},"savedGroups":{"g":["a"]}}')
      repo.fetch

      expect(repo.snapshot).to eq([{ 'f' => { 'defaultValue' => 1 } }, { 'g' => ['a'] }])
    end

    it 'keeps the previous pair when the new features fail to decrypt' do
      repo = described_class.new(endpoint: endpoint, decryption_key: 'BhB1wORFmZLTDjbvstvS8w==')
      stub_request(:get, endpoint)
        .to_return(status: 200, body: { encryptedFeatures: encrypted_features, savedGroups: { g: ['old'] } }.to_json)
        .then.to_return(status: 200, body: { encryptedFeatures: 'broken.payload', savedGroups: { g: ['new'] } }.to_json)
      repo.fetch
      before = repo.snapshot

      repo.fetch

      expect(repo.snapshot).to eq(before)
      expect(repo.saved_groups_json).to eq({ 'g' => ['old'] })
    end
  end

  describe 'auto refresh after a fork' do
    # Serves the features endpoint once, then streams a "features" event with a growing counter
    def start_counting_server(server)
      Thread.new do
        loop { Thread.new(server.accept) { |socket| serve_counting(socket) } }
      rescue IOError
        nil # the server was closed after the example
      end
    end

    def serve_counting(socket)
      path = socket.gets.to_s.split[1].to_s
      while (line = socket.gets) && line != "\r\n"; end
      return socket.write(features_response) if path.include?('/api/features/')

      socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n")
      1.step { |n| socket.write("event: features\ndata: #{payload(n)}\n\n") && sleep(0.05) }
    rescue IOError, SystemCallError
      nil # the client went away
    ensure
      socket.close
    end

    def features_response
      body = payload(0)
      "HTTP/1.1 200 OK\r\nx-sse-support: enabled\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    end

    def payload(count)
      { features: { count: { defaultValue: count } } }.to_json
    end

    def count(repo)
      repo.features_json['count']['defaultValue']
    end

    it 'starts a new stream in the child process' do
      skip 'fork is not available on this platform' unless Process.respond_to?(:fork)

      WebMock.disable! # WebMock buffers a real response to its end, and this stream never ends
      server = TCPServer.new('127.0.0.1', 0)
      start_counting_server(server)
      repo = described_class.new(endpoint: "http://127.0.0.1:#{server.addr[1]}/api/features/sdk-fork", decryption_key: nil)
      repo.fetch
      repo.start_auto_refresh

      reader, writer = IO.pipe
      pid = fork do
        reader.close
        first = count(repo)
        sleep 0.5
        writer.write(count(repo) > first ? 'updated' : 'stale')
        writer.close
        exit!(0) # skip the parent's at_exit hooks (RSpec, SimpleCov) in the child
      end
      writer.close
      result = reader.read
      Process.wait(pid)

      expect(result).to eq('updated')
    ensure
      repo&.stop_auto_refresh
      server&.close
      WebMock.enable!
    end
  end

  describe '#saved_groups_json' do
    subject(:repository) do
      described_class.new(endpoint: endpoint, decryption_key: decryption_key)
    end

    before do
      stub_request(:get, endpoint)
        .to_return(status: 200, body: json_response, headers: {})
    end

    context 'when the payload includes savedGroups' do
      let(:decryption_key) { nil }
      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-with-groups' }
      let(:json_response) do
        <<~JSON
          {
            "status": 200,
            "features": {},
            "savedGroups": { "admins": ["user-1", "user-2"], "beta": [123, 456] }
          }
        JSON
      end

      it 'exposes the parsed saved groups' do
        repository.fetch
        expect(repository.saved_groups_json).to eq(
          'admins' => %w[user-1 user-2],
          'beta'   => [123, 456]
        )
      end
    end

    context 'when the payload has no savedGroups' do
      let(:decryption_key) { nil }
      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-no-groups' }
      let(:json_response) { '{ "status": 200, "features": {} }' }

      it 'defaults to an empty hash' do
        repository.fetch
        expect(repository.saved_groups_json).to eq({})
      end
    end

    context 'when the payload includes encryptedSavedGroups' do
      let(:decryption_key) { 'BhB1wORFmZLTDjbvstvS8w==' }
      let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-encrypted-groups' }
      let(:json_response) do
        <<~JSON
          {
            "status": 200,
            "features": {},
            "encryptedFeatures": "Utj/Xwn7YaTXX8vHosRFQg==.yYuNdFoTv1aebOyhC7lTUpNSUW9toE4nSTMATKaT3mGwrzUUMrGg/3uJ0edpxRdoZcAD778+eDBlT9+i/wc+eMzBTK9KkEWSZG/hljlZjRP8zVbfggm/yy1E87xsGl1JnSkQ+iRyMTsrdEvvo2AkoQqFbmEOvOklcYAIZTMaYsgCOi+9BRbI1s6HLpI/kCE4kcuhePY0b20oWrpDL++wDQ==",
            "encryptedSavedGroups": "jUmZ+agHSAI5JKtNty1zqQ==.rkUx/e1//+46KeWjlZQGb4rtj/1t6FUVpkrCQJiyEJ/+qmsrAEsVh7tLRZA+eskF"
          }
        JSON
      end

      it 'exposes the decrypted saved groups' do
        repository.fetch
        expect(repository.saved_groups_json).to eq(
          'admins' => %w[user-1 user-2],
          'beta'   => [123, 456]
        )
      end
    end
  end

  describe '#sse_supported?' do
    subject(:repo) { described_class.new(endpoint: endpoint, decryption_key: nil) }

    let(:endpoint) { 'https://cdn.growthbook.io/api/features/sdk-abc123' }

    it 'is false before the first fetch' do
      expect(repo.sse_supported?).to be(false)
    end

    it 'is true when the server sends x-sse-support: enabled' do
      stub_request(:get, endpoint).to_return(status: 200, body: '{"features":{}}', headers: { 'x-sse-support' => 'enabled' })
      repo.fetch

      expect(repo.sse_supported?).to be(true)
    end

    it 'stays true when a later fetch gets an error response' do
      stub_request(:get, endpoint)
        .to_return(status: 200, body: '{"features":{}}', headers: { 'x-sse-support' => 'enabled' })
        .then.to_return(status: 502, body: 'Bad Gateway')
      repo.fetch
      repo.fetch

      expect(repo.sse_supported?).to be(true)
    end

    it 'is false when the header is missing' do
      stub_request(:get, endpoint).to_return(status: 200, body: '{"features":{}}')
      repo.fetch

      expect(repo.sse_supported?).to be(false)
    end
  end
end
