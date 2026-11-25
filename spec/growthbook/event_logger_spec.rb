# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

describe 'Growthbook::Context event logger' do
  let(:events) { [] }
  let(:event_logger) { ->(name, properties, user_context) { events << [name, properties, user_context] } }
  let(:context_options) { { attributes: attributes, features: features, url: 'https://example.test/page', event_logger: event_logger } }
  let(:gb) { Growthbook::Context.new(context_options) }

  def attributes
    { 'id' => 'user-123', 'country' => 'UA' }
  end

  def features
    {
      'flag'       => { 'defaultValue' => false },
      'by_country' => {
        'defaultValue' => 'default',
        'rules'        => [{ 'id' => 'fr_1', 'condition' => { 'country' => 'UA' }, 'force' => 'ua' }]
      },
      'experiment' => {
        'defaultValue' => 0,
        'rules'        => [{ 'id' => 'fr_2', 'key' => 'exp-1', 'variations' => [1, 2], 'meta' => [{ 'key' => 'control' }, { 'key' => 'treatment' }] }]
      }
    }
  end

  def event_names
    events.map(&:first)
  end

  describe 'Feature Evaluated' do
    it 'reports a default value with the $default rule id' do
      gb.eval_feature('flag')

      expect(events).to eq(
        [
          [
            'Feature Evaluated',
            { 'feature' => 'flag', 'source' => 'defaultValue', 'value' => false, 'ruleId' => '$default', 'variationId' => '' },
            { attributes: attributes, url: 'https://example.test/page' }
          ]
        ]
      )
    end

    it 'reports the rule id of a force rule' do
      gb.eval_feature('by_country')

      expect(events.first[1]).to eq(
        { 'feature' => 'by_country', 'source' => 'force', 'value' => 'ua', 'ruleId' => 'fr_1', 'variationId' => '' }
      )
    end

    it 'reports the variation key of an experiment rule' do
      gb.eval_feature('experiment')

      feature_event = events.find { |name, _| name == 'Feature Evaluated' }
      expect(feature_event[1]).to include('feature' => 'experiment', 'source' => 'experiment', 'ruleId' => 'fr_2')
      expect(feature_event[1]['variationId']).to eq('control').or eq('treatment')
    end

    it 'is sent once per feature until its value changes' do
      gb.eval_feature('by_country')
      gb.on?('by_country')
      gb.feature_value('by_country')
      expect(events.length).to eq(1)

      gb.attributes = { 'id' => 'user-123', 'country' => 'PL' }
      gb.eval_feature('by_country')
      gb.eval_feature('by_country')

      expect(events.map { |_, properties, _| properties['value'] }).to eq(%w[ua default])
    end

    it 'is not sent for forced feature values' do
      context_options[:forced_features] = { 'flag' => true }

      gb.eval_feature('flag')

      expect(events).to be_empty
    end

    it 'is sent again for a different user with the same value' do
      gb.eval_feature('by_country')
      gb.attributes = { 'id' => 'user-456', 'country' => 'UA' }
      gb.eval_feature('by_country')

      expect(events.map { |_, properties, user_context| [properties['value'], user_context[:attributes]['id']] }).to eq(
        [%w[ua user-123], %w[ua user-456]]
      )
    end

    it 'is not sent again when the same attributes are set again' do
      gb.eval_feature('by_country')
      gb.attributes = { id: 'user-123', country: 'UA' }
      gb.eval_feature('by_country')

      expect(events.length).to eq(1)
    end

    it 'dedupes values that cannot be serialized to JSON' do
      context_options[:features] = { 'ratio' => { 'defaultValue' => Float::NAN } }

      gb.eval_feature('ratio')
      gb.eval_feature('ratio')

      expect(events.length).to eq(1)
      expect(events.first[1]['value']).to be_nan
    end

    it 'is sent for unknown features' do
      gb.eval_feature('missing')

      expect(events.first[1]).to include('feature' => 'missing', 'source' => 'unknownFeature', 'value' => nil)
    end
  end

  describe 'Experiment Viewed' do
    let(:experiment) { Growthbook::InlineExperiment.new(key: 'inline-exp', variations: %w[a b]) }

    it 'reports the assignment, even without a listener' do
      result = gb.run(experiment)

      expect(events).to eq(
        [
          [
            'Experiment Viewed',
            { 'experimentId' => 'inline-exp', 'variationId' => result.key, 'hashAttribute' => 'id', 'hashValue' => 'user-123' },
            { attributes: attributes, url: 'https://example.test/page' }
          ]
        ]
      )
    end

    it 'is sent once per unit, experiment and variation' do
      gb.run(experiment)
      gb.run(experiment)
      expect(event_names).to eq(['Experiment Viewed'])

      gb.attributes = { 'id' => 'user-456' }
      gb.run(experiment)

      expect(events.map { |_, properties, _| properties['hashValue'] }).to eq(%w[user-123 user-456])
    end

    it 'does not confuse assignments whose key parts run together' do
      # 'user-1' + '2-exp' and 'user-12' + '-exp' would build the same key if concatenated
      always_first = { variations: %w[a b], weights: [1.0, 0.0] }
      context_options[:attributes] = { 'id' => 'user-1' }
      gb.run(Growthbook::InlineExperiment.new(always_first.merge(key: '2-exp')))
      gb.attributes = { 'id' => 'user-12' }
      gb.run(Growthbook::InlineExperiment.new(always_first.merge(key: '-exp')))

      expect(events.map { |_, properties, _| properties['experimentId'] }).to eq(%w[2-exp -exp])
    end

    it 'forgets the least recently seen assignment once the limit is reached' do
      stub_const('Growthbook::Context::TRACKED_EXPERIMENTS_LIMIT', 2)
      run_as = lambda do |id|
        gb.attributes = { 'id' => id }
        gb.run(experiment)
      end

      %w[user-1 user-2 user-1 user-3].each(&run_as)
      expect(events.map { |_, properties, _| properties['hashValue'] }).to eq(%w[user-1 user-2 user-3])

      # user-1 was seen more recently than user-2, so user-2 was evicted and is reported again
      %w[user-1 user-2].each(&run_as)
      expect(events.map { |_, properties, _| properties['hashValue'] }).to eq(%w[user-1 user-2 user-3 user-2])
    end

    it 'is sent alongside Feature Evaluated for an experiment rule' do
      gb.eval_feature('experiment')

      expect(event_names).to eq(['Experiment Viewed', 'Feature Evaluated'])
      expect(events.first[1]).to include('experimentId' => 'exp-1')
    end

    it 'is not sent when the user is not in the experiment' do
      context_options[:attributes] = {}

      gb.run(experiment)

      expect(events).to be_empty
    end

    it 'does not change how often the listener is called' do
      listener = double
      allow(listener).to receive(:on_experiment_viewed)
      context_options[:listener] = listener

      gb.run(experiment)
      gb.run(experiment)

      expect(listener).to have_received(:on_experiment_viewed).twice
      expect(event_names).to eq(['Experiment Viewed'])
    end
  end

  describe 'user context' do
    it 'is a copy of the attributes at the time of the event' do
      gb.eval_feature('flag')
      events.first[2][:attributes]['id'] = 'changed'

      expect(gb.attributes['id']).to eq('user-123')
    end

    it 'has a nil url when none is set' do
      context_options.delete(:url)

      gb.eval_feature('flag')

      expect(events.first[2]).to eq({ attributes: attributes, url: nil })
    end
  end

  describe 'a logger that raises' do
    let(:event_logger) { ->(*) { raise StandardError, 'ingestor down' } }

    it 'does not break evaluation' do
      expect(gb.eval_feature('by_country').value).to eq('ua')
      expect(gb.eval_feature('experiment').source).to eq('experiment')
    end
  end

  describe 'event_logger=' do
    it 'starts sending events once set' do
      context_options.delete(:event_logger)

      gb.eval_feature('flag')
      gb.event_logger = event_logger
      gb.eval_feature('by_country')

      expect(events.map { |_, properties, _| properties['feature'] }).to eq(['by_country'])
    end

    it 'accepts any object that responds to call' do
      logger = Class.new do
        attr_reader :names

        def initialize
          @names = []
        end

        def call(name, _properties, _user_context)
          @names << name
        end
      end.new
      context_options[:event_logger] = logger

      gb.eval_feature('flag')

      expect(logger.names).to eq(['Feature Evaluated'])
    end
  end

  describe '#log_event' do
    it 'sends a custom event with its properties and the user context' do
      gb.log_event('Button Clicked', { 'button' => 'signup' })

      expect(events).to eq(
        [['Button Clicked', { 'button' => 'signup' }, { attributes: attributes, url: 'https://example.test/page' }]]
      )
    end

    it 'sends empty properties by default' do
      gb.log_event('Page Viewed')
      gb.log_event('Page Left', nil)

      expect(events.map { |_, properties, _| properties }).to eq([{}, {}])
    end

    it 'warns when no event logger is configured' do
      context_options.delete(:event_logger)

      expect { gb.log_event('Page Viewed') }.to output(/No event logger configured/).to_stderr
    end

    it 'warns instead of raising when the logger raises' do
      context_options[:event_logger] = ->(*) { raise StandardError, 'ingestor down' }

      expect { gb.log_event('Page Viewed') }.to output(/ingestor down/).to_stderr
    end
  end
end
