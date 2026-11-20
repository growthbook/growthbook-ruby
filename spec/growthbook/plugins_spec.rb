# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

describe 'Growthbook::Context plugins' do
  let(:context_options) do
    {
      attributes: { 'id' => 'user-123' },
      features: { 'flag' => { 'defaultValue' => true } },
      client_key: 'sdk-test'
    }
  end

  it 'calls each plugin once with the context, in order' do
    calls = []
    first = ->(gb) { calls << [:first, gb] }
    second = ->(gb) { calls << [:second, gb] }

    gb = Growthbook::Context.new(context_options.merge(plugins: [first, second]))

    expect(calls).to eq([[:first, gb], [:second, gb]])
  end

  it 'runs once the context is fully set up' do
    seen = nil
    plugin = ->(gb) { seen = [gb.client_key, gb.attributes, gb.on?('flag')] }

    Growthbook::Context.new(context_options.merge(plugins: [plugin]))

    expect(seen).to eq(['sdk-test', { 'id' => 'user-123' }, true])
  end

  it 'lets a plugin set up the event logger and register on_destroy' do
    events = []
    destroyed = false
    plugin = lambda do |gb|
      gb.event_logger = ->(name, _properties, _user_context) { events << name }
      gb.on_destroy { destroyed = true }
    end

    gb = Growthbook::Context.new(context_options.merge(plugins: [plugin]))
    gb.on?('flag')
    gb.destroy

    expect(events).to eq(['Feature Evaluated'])
    expect(destroyed).to be(true)
  end

  it 'accepts any object that responds to call' do
    plugin = Class.new do
      attr_reader :context

      def call(context)
        @context = context
      end
    end.new

    gb = Growthbook::Context.new(context_options.merge(plugins: [plugin]))

    expect(plugin.context).to be(gb)
  end

  it 'ignores nil and empty plugin lists' do
    expect { Growthbook::Context.new(context_options.merge(plugins: nil)) }.not_to output.to_stderr
    expect { Growthbook::Context.new(context_options.merge(plugins: [])) }.not_to output.to_stderr
  end

  it 'does not rescue an error raised by a plugin' do
    plugin = ->(_gb) { raise StandardError, 'plugin broken' }

    expect { Growthbook::Context.new(context_options.merge(plugins: [plugin])) }.to raise_error(StandardError, 'plugin broken')
  end

  it 'rejects a plugin that does not respond to call' do
    expect { Growthbook::Context.new(context_options.merge(plugins: ['tracking'])) }
      .to raise_error(ArgumentError, /must respond to #call, got String/)
  end
end
