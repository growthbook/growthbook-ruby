# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

RSpec.describe Growthbook::SSEParser do
  subject(:parser) { described_class.new }

  # Feeds every chunk and returns all events the parser yielded
  def parse(*chunks)
    events = []
    chunks.each { |chunk| parser.feed(chunk) { |event| events << event } }
    events
  end

  describe '#feed' do
    it 'yields an event finished by an empty line' do
      expect(parse("event: features\ndata: {}\n\n")).to eq([{ type: 'features', data: '{}' }])
    end

    it 'joins a line split across chunks' do
      expect(parse("event: a\nda", "ta: x\n\n")).to eq([{ type: 'a', data: 'x' }])
    end

    it 'yields every event in a single chunk' do
      expect(parse("event: a\ndata: 1\n\nevent: b\ndata: 2\n\n")).to eq(
        [{ type: 'a', data: '1' }, { type: 'b', data: '2' }]
      )
    end

    it 'joins several data lines with a newline' do
      expect(parse("event: a\ndata: 1\ndata: 2\n\n")).to eq([{ type: 'a', data: "1\n2" }])
    end

    it 'yields an event without data lines' do
      expect(parse("event: features-updated\n\n")).to eq([{ type: 'features-updated', data: '' }])
    end

    it 'accepts CRLF line endings' do
      expect(parse("event: a\r\ndata: x\r\n\r\n")).to eq([{ type: 'a', data: 'x' }])
    end

    it 'ignores comment lines' do
      expect(parse(": ping\n\n")).to eq([])
    end

    it 'drops an event without an event line' do
      expect(parse("data: x\n\n")).to eq([])
    end

    it 'holds back an event until the empty line arrives' do
      expect(parse("event: a\ndata: x\n")).to eq([])
    end

    it 'keeps colons in the value' do
      expect(parse("event: a\ndata: {\"a\":1}\n\n")).to eq([{ type: 'a', data: '{"a":1}' }])
    end
  end

  describe '#finish' do
    # Feeds the chunk, then returns what finish yields
    def finish_after(chunk)
      parser.feed(chunk)
      events = []
      parser.finish { |event| events << event }
      events
    end

    it 'yields an event the stream closed before finishing' do
      expect(finish_after("event: a\ndata: x")).to eq([{ type: 'a', data: 'x' }])
    end

    it 'yields nothing a second time' do
      finish_after("event: a\ndata: x\n")

      events = []
      parser.finish { |event| events << event }
      expect(events).to eq([])
    end
  end
end
