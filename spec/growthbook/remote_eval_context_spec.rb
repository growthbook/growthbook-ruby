# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'json'

RSpec.describe 'Growthbook::Context remote evaluation' do
  let(:endpoint) { 'https://gb-proxy.example.com/api/eval/sdk-abc123' }
  let(:repository) do
    Growthbook::RemoteEvalRepository.new(
      api_host: 'https://gb-proxy.example.com',
      client_key: 'sdk-abc123',
      cache: nil
    )
  end

  def stub_eval(banner_text, saved_groups = {})
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: JSON.generate(
        'features'    => { 'banner_text' => { 'defaultValue' => banner_text } },
        'savedGroups' => saved_groups
      )
    )
  end

  describe 'initialization' do
    it 'loads the remotely evaluated features' do
      stub_eval('Welcome')

      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      expect(gb.feature_value('banner_text')).to eq('Welcome')
      expect(gb.remote_eval?).to be(true)
    end

    it 'loads the remotely evaluated saved groups' do
      stub_eval('Welcome', 'beta' => %w[1 2])

      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      expect(gb.saved_groups).to eq('beta' => %w[1 2])
    end

    it 'sends the initial context once' do
      stub = stub_eval('Welcome')

      Growthbook::Context.new(
        remote_eval_repository: repository,
        attributes: { id: '1' },
        forced_variations: { 'exp' => 1 }
      )

      expect(stub).to have_been_requested.once
    end

    it 'keeps working when the proxy is unreachable' do
      stub_request(:post, endpoint).to_return(status: 500)

      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      expect(gb.feature_value('banner_text', 'fallback')).to eq('fallback')
    end

    it 'rejects a sticky bucket service' do
      expect do
        Growthbook::Context.new(
          remote_eval_repository: repository,
          sticky_bucket_service: Growthbook::InMemoryStickyBucketService.new
        )
      end.to raise_error(ArgumentError, /sticky_bucket_service/)
    end

    it 'rejects a decryption key' do
      expect do
        Growthbook::Context.new(remote_eval_repository: repository, decryption_key: 'some-key')
      end.to raise_error(ArgumentError, /decryption_key/)
    end
  end

  describe 're-evaluation when the context changes' do
    it 're-evaluates when the attributes are replaced' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_eval('Bienvenue')
      gb.attributes = { id: '1', country: 'FR' }

      expect(gb.feature_value('banner_text')).to eq('Bienvenue')
    end

    it 'sends the new attributes in the payload' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub = stub_request(:post, endpoint).with(
        body: hash_including('attributes' => { 'id' => '1', 'country' => 'FR' })
      ).to_return(status: 200, body: JSON.generate('features' => { 'banner_text' => { 'defaultValue' => 'Bienvenue' } }))

      gb.attributes = { id: '1', country: 'FR' }

      expect(stub).to have_been_requested.once
      expect(gb.feature_value('banner_text')).to eq('Bienvenue')
    end

    it 're-evaluates when the forced variations change' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub = stub_request(:post, endpoint).with(
        body: hash_including('forcedVariations' => { 'exp' => 1 })
      ).to_return(status: 200, body: JSON.generate('features' => {}))

      gb.forced_variations = { 'exp' => 1 }

      expect(stub).to have_been_requested.once
    end

    it 're-evaluates when the forced features change' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub = stub_request(:post, endpoint).with(
        body: hash_including('forcedFeatures' => [%w[banner_text Forced]])
      ).to_return(status: 200, body: JSON.generate('features' => {}))

      gb.forced_features = { 'banner_text' => 'Forced' }

      expect(stub).to have_been_requested.once
    end

    it 're-evaluates when the url changes' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub = stub_request(:post, endpoint).with(
        body: hash_including('url' => 'https://example.com/pricing')
      ).to_return(status: 200, body: JSON.generate('features' => {}))

      gb.url = 'https://example.com/pricing'

      expect(stub).to have_been_requested.once
      expect(gb.url).to eq('https://example.com/pricing')
    end

    it 'does not report the previous context features when re-evaluation fails' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_request(:post, endpoint).to_return(status: 500)
      gb.attributes = { id: '1', country: 'FR' }

      expect(gb.feature_value('banner_text', 'fallback')).to eq('fallback')
    end

    it 'serves an unchanged context from the cache' do
      cached_repository = Growthbook::RemoteEvalRepository.new(
        api_host: 'https://gb-proxy.example.com',
        client_key: 'sdk-abc123'
      )
      stub = stub_eval('Welcome')

      gb = Growthbook::Context.new(remote_eval_repository: cached_repository, attributes: { id: '1' })
      gb.attributes = { id: '1' }

      expect(stub).to have_been_requested.once
    end
  end

  describe '#refresh_for_remote_eval' do
    it 'picks up features that changed on the server' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_eval('Bienvenue')

      expect(gb.refresh_for_remote_eval).to be(true)
      expect(gb.feature_value('banner_text')).to eq('Bienvenue')
    end

    it 'reports a failed refresh' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_request(:post, endpoint).to_return(status: 500)

      expect(gb.refresh_for_remote_eval).to be(false)
    end
  end

  describe 'without remote evaluation' do
    subject(:gb) { Growthbook::Context.new(features: { 'banner_text' => { 'defaultValue' => 'Local' } }) }

    it 'is not in remote eval mode' do
      expect(gb.remote_eval?).to be(false)
    end

    it 'makes no request when the context changes' do
      gb.attributes = { id: '1' }
      gb.url = 'https://example.com'

      expect(gb.feature_value('banner_text')).to eq('Local')
    end

    it 'reports refresh as a no-op' do
      expect(gb.refresh_for_remote_eval).to be(false)
    end
  end

  describe 'when a refresh fails' do
    it 'keeps the features when the context has not changed' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_request(:post, endpoint).to_return(status: 500)
      gb.refresh_for_remote_eval

      expect(gb.feature_value('banner_text')).to eq('Welcome')
    end

    it 'discards features belonging to a different context' do
      stub_eval('Welcome')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_request(:post, endpoint).to_return(status: 500)
      gb.attributes = { id: '2' }

      expect(gb.feature_value('banner_text', 'fallback')).to eq('fallback')
    end

    it 'discards the saved groups with them' do
      stub_eval('Welcome', 'beta' => %w[1 2])
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' })

      stub_request(:post, endpoint).to_return(status: 500)
      gb.attributes = { id: '2' }

      expect(gb.saved_groups).to eq({})
    end

    it 'keeps features the caller supplied rather than the proxy' do
      stub_request(:post, endpoint).to_return(status: 500)

      gb = Growthbook::Context.new(
        remote_eval_repository: repository,
        attributes: { id: '1' },
        features: { 'banner_text' => { 'defaultValue' => 'local' } }
      )

      expect(gb.feature_value('banner_text')).to eq('local')
    end
  end

  describe 'tracking experiments evaluated on the proxy' do
    let(:listener) { Class.new(Growthbook::TrackingCallback) { def on_experiment_viewed(_experiment, _result); end }.new }
    let(:track) do
      {
        'experiment' => {
          'key'           => 'checkout-exp',
          'variations'    => [{}, 'green'],
          'hashAttribute' => 'id',
          'name'          => 'Checkout experiment'
        },
        'result'     => {
          'key'              => '1',
          'name'             => 'Variation 1',
          'featureId'        => 'button_color',
          'inExperiment'     => true,
          'hashUsed'         => true,
          'variationId'      => 1,
          'value'            => 'green',
          'hashAttribute'    => 'id',
          'hashValue'        => '1',
          'stickyBucketUsed' => false,
          'bucket'           => 0.5726
        }
      }
    end

    def stub_tracked_eval(rule)
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: JSON.generate('features' => { 'button_color' => { 'defaultValue' => 'blue', 'rules' => [rule] } })
      )
    end

    before { allow(listener).to receive(:on_experiment_viewed) }

    it 'fires the tracking callback for each track on the matched rule' do
      stub_tracked_eval('force' => 'green', 'tracks' => [track])
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' }, listener: listener)

      expect(gb.feature_value('button_color')).to eq('green')
      expect(listener).to have_received(:on_experiment_viewed).once do |experiment, result|
        expect(experiment.key).to eq('checkout-exp')
        expect(experiment.variations).to eq([{}, 'green'])
        expect(experiment.name).to eq('Checkout experiment')
        expect(result.to_json).to eq(track['result'])
      end
    end

    it 'records the impression' do
      stub_tracked_eval('force' => 'green', 'tracks' => [track])
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' }, listener: listener)

      gb.eval_feature('button_color')

      expect(gb.impressions['checkout-exp'].variation_id).to eq(1)
    end

    it 'does not fire for a force rule without tracks' do
      stub_tracked_eval('force' => 'green')
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' }, listener: listener)

      gb.eval_feature('button_color')

      expect(listener).not_to have_received(:on_experiment_viewed)
    end

    it 'does not fire when the rule is skipped' do
      stub_tracked_eval('force' => 'green', 'condition' => { 'country' => 'US' }, 'tracks' => [track])
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' }, listener: listener)

      expect(gb.feature_value('button_color')).to eq('blue')
      expect(listener).not_to have_received(:on_experiment_viewed)
    end

    it 'skips malformed tracks without breaking the evaluation' do
      malformed = [nil, 'oops', { 'experiment' => { 'variations' => [] }, 'result' => {} }, { 'experiment' => track['experiment'] }]
      stub_tracked_eval('force' => 'green', 'tracks' => malformed + [track])
      gb = Growthbook::Context.new(remote_eval_repository: repository, attributes: { id: '1' }, listener: listener)

      expect(gb.feature_value('button_color')).to eq('green')
      expect(listener).to have_received(:on_experiment_viewed).once
    end

    it 'fires for tracks on locally supplied features too' do
      gb = Growthbook::Context.new(
        features: { 'button_color' => { 'defaultValue' => 'blue', 'rules' => [{ 'force' => 'green', 'tracks' => [track] }] } },
        listener: listener
      )

      gb.eval_feature('button_color')

      expect(listener).to have_received(:on_experiment_viewed).once
    end
  end
end
