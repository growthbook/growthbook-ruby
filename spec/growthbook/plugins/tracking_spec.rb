# frozen_string_literal: true

require_relative '../../spec_helper'
require 'growthbook'

describe Growthbook::Plugins::Tracking do
  let(:requests) { [] }
  let(:tracker_options) { { queue_flush_interval: 10 } }
  let(:tracker) { described_class.new(**tracker_options) }

  def endpoint
    'https://us-east-1.gb-ingest.com/track?client_key=sdk-test'
  end

  def attributes
    { 'id' => 'user-123', 'country' => 'UA' }
  end

  def features
    { 'flag' => { 'defaultValue' => true }, 'other' => { 'defaultValue' => 1 } }
  end

  before do
    stub_request(:post, endpoint).to_return do |request|
      requests << request
      { status: 200 }
    end
  end

  after do
    # Tests that fake a fork stub Process.pid; shut down as the real process so nothing is left
    # for the at_exit hook to send once WebMock is gone
    allow(Process).to receive(:pid).and_call_original
    tracker.shutdown
  end

  def context(options = {})
    Growthbook::Context.new({ client_key: 'sdk-test', attributes: attributes, features: features, plugins: [tracker] }.merge(options))
  end

  def sent_events
    tracker.shutdown
    requests.flat_map { |request| JSON.parse(request.body) }
  end

  def wait_for_request(timeout: 2)
    deadline = Time.now + timeout
    sleep(0.01) while requests.empty? && Time.now < deadline
  end

  it 'requires a client key' do
    expect { context(client_key: nil) }.to raise_error(ArgumentError, /client_key must be specified/)
  end

  it 'rejects an ingestor host that is not an http(s) URL' do
    expect { described_class.new(ingestor_host: 'gb-ingest.test') }.to raise_error(ArgumentError, /ingestor_host/)
  end

  it 'sends a Feature Evaluated event with the user split into identity fields and context' do
    gb = context(
      attributes: { 'id' => 'user-123', 'session_id' => 'session-1', 'utmSource' => 'newsletter', 'utmTerm' => '', 'country' => 'UA' },
      url: 'https://example.test/page'
    )

    gb.on?('flag')

    expect(sent_events).to eq(
      [
        {
          'event_name'      => 'Feature Evaluated',
          'properties_json' => { 'feature' => 'flag', 'source' => 'defaultValue', 'value' => true, 'ruleId' => '$default', 'variationId' => '' },
          'user_id'         => nil,
          'device_id'       => 'user-123',
          'page_id'         => nil,
          'session_id'      => 'session-1',
          'utm_source'      => 'newsletter',
          'sdk_language'    => 'ruby',
          'sdk_version'     => Growthbook::VERSION,
          'url'             => 'https://example.test/page',
          'context_json'    => { 'country' => 'UA' }
        }
      ]
    )
  end

  it 'posts the batch as text/plain to the client key endpoint' do
    context.on?('flag')
    sent_events

    expect(WebMock).to have_requested(:post, endpoint)
                         .with(headers: { 'Content-Type' => 'text/plain', 'Accept' => 'application/json' }).once
  end

  it 'prefers device_id, then anonymous_id, then id, and only sends strings' do
    context(attributes: { 'user_id' => 42, 'anonymous_id' => 'anon-1', 'id' => 'user-123' }).on?('flag')

    expect(sent_events.first.values_at('user_id', 'device_id')).to eq([nil, 'anon-1'])
  end

  it 'sends the events of many evaluations in one request' do
    gb = context
    gb.on?('flag')
    gb.on?('other')
    gb.log_event('Checkout Started', { 'step' => 1 })

    expect(sent_events.map { |event| event['event_name'] }).to eq(['Feature Evaluated', 'Feature Evaluated', 'Checkout Started'])
    expect(requests.length).to eq(1)
  end

  it 'sends one request per client key' do
    stub_request(:post, 'https://us-east-1.gb-ingest.com/track?client_key=sdk-other').to_return do |request|
      requests << request
      { status: 200 }
    end

    context.on?('flag')
    context(client_key: 'sdk-other').on?('flag')

    expect(sent_events.length).to eq(2)
    expect(requests.map { |request| request.uri.query }).to contain_exactly('client_key=sdk-test', 'client_key=sdk-other')
  end

  it 'sends Experiment Viewed events' do
    context.run(Growthbook::InlineExperiment.new(key: 'exp-1', variations: %w[a b]))

    expect(sent_events.first).to include(
      'event_name'      => 'Experiment Viewed',
      'properties_json' => include('experimentId' => 'exp-1', 'hashAttribute' => 'id', 'hashValue' => 'user-123')
    )
  end

  describe 'deduplication' do
    it 'skips the same event for the same user across contexts' do
      context.on?('flag')
      context.on?('flag')

      expect(sent_events.length).to eq(1)
    end

    it 'keeps Feature Evaluated of different users apart' do
      context.on?('flag')
      context(attributes: { 'id' => 'user-456' }).on?('flag')

      expect(sent_events.map { |event| event['device_id'] }).to eq(%w[user-123 user-456])
    end

    it 'can identify users by the dedupe_key_attributes only' do
      tracker_options[:dedupe_key_attributes] = [:id]

      context.on?('flag')
      context(attributes: { 'id' => 'user-123', 'country' => 'PL' }).on?('flag')

      expect(sent_events.length).to eq(1)
    end

    it 'forgets the least recently seen event once dedupe_cache_size is reached' do
      tracker_options[:dedupe_cache_size] = 1

      %w[user-1 user-2 user-1].each { |id| context(attributes: { 'id' => id }).on?('flag') }

      expect(sent_events.map { |event| event['device_id'] }).to eq(%w[user-1 user-2 user-1])
    end

    it 'does not dedupe custom events' do
      gb = context
      gb.log_event('Button Clicked')
      gb.log_event('Button Clicked')

      expect(sent_events.length).to eq(2)
    end
  end

  describe 'options' do
    it 'does not send Feature Evaluated when enable_feature_usage_events is false' do
      tracker_options[:enable_feature_usage_events] = false
      gb = context

      gb.on?('flag')
      gb.run(Growthbook::InlineExperiment.new(key: 'exp-1', variations: %w[a b]))

      expect(sent_events.map { |event| event['event_name'] }).to eq(['Experiment Viewed'])
    end

    it 'drops events the event_filter rejects' do
      seen = []
      tracker_options[:event_filter] = lambda do |data|
        seen << data
        data[:event_name] != 'Feature Evaluated'
      end
      gb = context(url: 'https://example.test/page')

      gb.on?('flag')
      gb.log_event('Page Viewed')

      expect(sent_events.map { |event| event['event_name'] }).to eq(['Page Viewed'])
      expect(seen.first).to include(event_name: 'Feature Evaluated', attributes: attributes, url: 'https://example.test/page')
    end

    it 'sends nothing when enable is false' do
      tracker_options[:enable] = false

      context.on?('flag')

      expect(sent_events).to be_empty
      expect(requests).to be_empty
    end

    it 'writes each event to stderr with debug' do
      tracker_options[:debug] = true

      expect { context.on?('flag') }.to output(/Logging event to GrowthBook: .*"event_name":"Feature Evaluated"/).to_stderr
    end

    it 'accepts an ingestor host with a trailing slash' do
      tracker_options[:ingestor_host] = 'https://gb-ingest.test/'
      stub_request(:post, 'https://gb-ingest.test/track?client_key=sdk-test').to_return do |request|
        requests << request
        { status: 200 }
      end

      context.on?('flag')

      expect(sent_events.length).to eq(1)
    end

    it 'drops events beyond max_queue_size and warns once' do
      tracker_options[:max_queue_size] = 1
      gb = context

      expect do
        gb.log_event('One')
        gb.log_event('Two')
        gb.log_event('Three')
      end.to output(/queue is full/).to_stderr
      expect(sent_events.map { |event| event['event_name'] }).to eq(['One'])
    end
  end

  describe 'sending' do
    it 'sends in the background after queue_flush_interval' do
      tracker_options[:queue_flush_interval] = 0.01

      context.on?('flag')
      wait_for_request

      expect(requests.length).to eq(1)
    end

    it 'sends right away when the context is destroyed' do
      gb = context
      gb.on?('flag')

      gb.destroy
      wait_for_request

      expect(requests.length).to eq(1)
    end

    it 'sends queued events with flush' do
      context.on?('flag')

      tracker.flush

      expect(requests.length).to eq(1)
    end

    it 'warns about a failed request without the response body' do
      stub_request(:post, endpoint).to_return(status: 500, body: 'user-123')
      context.on?('flag')

      expect { tracker.flush }.to output(/GrowthBook tracking failed: HTTP 500\n\z/).to_stderr
    end

    it 'warns about a network error with its class only' do
      stub_request(:post, endpoint).to_raise(StandardError.new('body: user-123'))
      context.on?('flag')

      expect { tracker.flush }.to output("GrowthBook tracking failed: StandardError\n").to_stderr
    end

    it 'drops an event that cannot be serialized and sends the rest' do
      gb = context

      expect { gb.log_event('Broken', { 'ratio' => Float::NAN }) }.to output(/can't be serialized/).to_stderr
      gb.log_event('Fine')

      expect(sent_events.map { |event| event['event_name'] }).to eq(['Fine'])
    end

    it 'drops events tracked after shutdown' do
      gb = context
      tracker.shutdown

      gb.on?('flag')

      expect(sent_events).to be_empty
    end
  end

  describe 'after a fork' do
    it 'leaves the events queued before the fork to the parent' do
      gb = context
      gb.log_event('Before fork')
      allow(Process).to receive(:pid).and_return(Process.pid + 1)

      gb.log_event('In child')
      tracker.flush

      expect(requests.flat_map { |request| JSON.parse(request.body) }.map { |event| event['event_name'] }).to eq(['In child'])
    end

    it 'does not send the copy of the parent queue at exit of a child that never tracked' do
      context.log_event('Before fork')
      allow(Process).to receive(:pid).and_return(Process.pid + 1)

      tracker.shutdown

      expect(requests).to be_empty
    end
  end
end
