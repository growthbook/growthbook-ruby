# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

describe 'Growthbook::Context lifecycle' do
  let(:events) { [] }
  let(:context_options) do
    {
      attributes: { 'id' => 'user-123' },
      features: { 'flag' => { 'defaultValue' => true } },
      event_logger: ->(name, properties, _user_context) { events << [name, properties] }
    }
  end
  let(:gb) { Growthbook::Context.new(context_options) }
  let(:experiment) { Growthbook::InlineExperiment.new(key: 'inline-exp', variations: %w[a b]) }

  describe '#client_key' do
    it 'is set from the options' do
      context_options[:client_key] = 'sdk-test'

      expect(gb.client_key).to eq('sdk-test')
    end

    it 'accepts the camelCase option name' do
      context_options[:clientKey] = 'sdk-test'

      expect(gb.client_key).to eq('sdk-test')
    end

    it 'is nil when not set' do
      expect(gb.client_key).to be_nil
    end
  end

  describe '#destroy' do
    it 'marks the context as destroyed' do
      expect(gb.destroyed?).to be(false)

      gb.destroy

      expect(gb.destroyed?).to be(true)
    end

    it 'runs the on_destroy callbacks in order, once' do
      calls = []
      gb.on_destroy { calls << :first }
      gb.on_destroy { calls << :second }

      gb.destroy
      gb.destroy

      expect(calls).to eq(%i[first second])
    end

    it 'runs the callbacks before clearing the impressions' do
      seen = nil
      # impressions are only recorded when there is a listener
      context_options[:listener] = Growthbook::TrackingCallback.new
      gb.on_destroy { seen = gb.impressions.keys }
      gb.run(experiment)

      gb.destroy

      expect(seen).to eq(['inline-exp'])
      expect(gb.impressions).to eq({})
    end

    it 'still runs the remaining callbacks when one raises' do
      calls = []
      gb.on_destroy { raise StandardError, 'flush failed' }
      gb.on_destroy { calls << :second }

      expect { gb.destroy }.to output(/on_destroy callback raised: StandardError: flush failed/).to_stderr
      expect(calls).to eq([:second])
    end

    it 'clears the event dedupe history' do
      gb.eval_feature('flag')
      gb.run(experiment)

      gb.destroy
      gb.eval_feature('flag')
      gb.run(experiment)

      expect(events.map(&:first)).to eq(['Feature Evaluated', 'Experiment Viewed'] * 2)
    end

    it 'keeps evaluating features, and still reports them to the event logger' do
      gb.destroy

      expect(gb.on?('flag')).to be(true)
      expect(events.map(&:first)).to eq(['Feature Evaluated'])
    end
  end

  describe '#on_destroy' do
    it 'requires a block' do
      expect { gb.on_destroy }.to raise_error(ArgumentError)
    end

    it 'warns and ignores a block registered after destroy' do
      calls = []
      gb.destroy

      expect { gb.on_destroy { calls << :late } }.to output(/Cannot register on_destroy callback/).to_stderr
      gb.destroy
      expect(calls).to be_empty
    end
  end

  describe '#log_event after destroy' do
    it 'warns and does not send the event' do
      gb.destroy

      expect { gb.log_event('Page Viewed') }.to output(/Cannot log event to destroyed GrowthBook context/).to_stderr
      expect(events).to be_empty
    end
  end
end
