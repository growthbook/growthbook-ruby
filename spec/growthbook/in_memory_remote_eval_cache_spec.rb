# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

RSpec.describe Growthbook::InMemoryRemoteEvalCache do
  subject(:cache) { described_class.new }

  it 'returns what was stored' do
    cache.set('a', { 'features' => {} }, 60)

    expect(cache.get('a')).to eq('features' => {})
  end

  it 'returns nil for an unknown key' do
    expect(cache.get('missing')).to be_nil
  end

  it 'expires an entry once its ttl has passed' do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    allow(Process).to receive(:clock_gettime).and_return(now)
    cache.set('a', 'value', 60)

    allow(Process).to receive(:clock_gettime).and_return(now + 61)

    expect(cache.get('a')).to be_nil
  end

  it 'keeps an entry with a ttl of zero forever' do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    allow(Process).to receive(:clock_gettime).and_return(now)
    cache.set('a', 'value', 0)

    allow(Process).to receive(:clock_gettime).and_return(now + 100_000)

    expect(cache.get('a')).to eq('value')
  end

  it 'overwrites an existing key' do
    cache.set('a', 'first', 60)
    cache.set('a', 'second', 60)

    expect(cache.get('a')).to eq('second')
  end

  describe 'lru eviction' do
    subject(:cache) { described_class.new(max_size: 2) }

    it 'evicts the least recently used entry' do
      cache.set('a', 'a', 60)
      cache.set('b', 'b', 60)
      cache.set('c', 'c', 60)

      expect(cache.get('a')).to be_nil
      expect(cache.get('b')).to eq('b')
      expect(cache.get('c')).to eq('c')
    end

    it 'counts a read as a use' do
      cache.set('a', 'a', 60)
      cache.set('b', 'b', 60)
      cache.get('a')
      cache.set('c', 'c', 60)

      expect(cache.get('a')).to eq('a')
      expect(cache.get('b')).to be_nil
    end

    context 'when the bound is disabled' do
      subject(:cache) { described_class.new(max_size: 0) }

      it 'keeps every entry' do
        20.times { |i| cache.set(i.to_s, i, 60) }

        expect(cache.get('0')).to eq(0)
      end
    end
  end
end
