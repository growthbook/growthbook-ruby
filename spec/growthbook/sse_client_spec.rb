# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'
require 'socket'

RSpec.describe Growthbook::SSEClient do
  def features_event
    "event: features\ndata: {}\n\n"
  end

  # Answers each new connection with the next [status, body] pair; the last pair repeats
  def start_server(server, responses)
    Thread.new do
      connections = 0
      loop do
        status, body = responses[[connections, responses.size - 1].min]
        connections += 1
        serve(server.accept, status, body)
      end
    rescue IOError
      nil # the server was closed after the example
    end
    "http://127.0.0.1:#{server.addr[1]}/sub/sdk-test"
  end

  # Reads the request, then writes a minimal HTTP response and closes the connection
  def serve(socket, status, body)
    socket.gets
    while (line = socket.gets) && line != "\r\n"; end
    socket.write("HTTP/1.1 #{status} X\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n#{body}")
    socket.close
  end

  # Polls until the block returns true or `timeout` seconds pass
  def wait_until(timeout = 2)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
  end

  it 'rejects a url without a host' do
    expect { described_class.new(url: '/sub/sdk-test', on_event: ->(_event) {}) }.to raise_error(ArgumentError)
  end

  describe 'streaming' do
    subject(:client) do
      described_class.new(
        url: start_server(server, responses),
        on_event: handler,
        reconnect_delay: reconnect_delay,
        max_reconnect_delay: 0.05
      )
    end

    let(:server) { TCPServer.new('127.0.0.1', 0) }
    let(:responses) { [[200, features_event]] }
    let(:reconnect_delay) { 0.01 }
    let(:events) { [] }
    let(:handler) { ->(event) { events << event } }

    before { WebMock.disable_net_connect!(allow_localhost: true) }

    after do
      client.stop
      server.close
      WebMock.disable_net_connect!
    end

    it 'delivers events from the stream' do
      client.start
      wait_until { events.any? }

      expect(events.first).to eq({ type: 'features', data: '{}' })
    end

    it 'returns from start at once and reports running until stopped' do
      client.start
      expect(client.running?).to be(true)

      client.stop
      expect(client.running?).to be(false)
    end

    context 'when the server fails before it succeeds' do
      let(:responses) { [[503], [200, features_event]] }

      it 'reconnects' do
        client.start
        wait_until { events.any? }

        expect(events.first[:type]).to eq('features')
      end
    end

    context 'when the server rejects the request' do
      let(:responses) { [[401]] }

      it 'gives up' do
        expect do
          client.start
          wait_until { !client.running? }
        end.to output(/answered 401/).to_stderr

        expect(client.running?).to be(false)
      end
    end

    context 'when the handler raises' do
      let(:handler) do
        lambda do |event|
          events << event
          raise 'boom'
        end
      end

      it 'keeps the stream going' do
        expect do
          client.start
          wait_until { events.size >= 2 }
        end.to output(/handler failed: boom/).to_stderr

        expect(client.running?).to be(true)
      end
    end

    context 'when the server sends a malformed response' do
      let(:responses) { [['bad'], [200, features_event]] }

      it 'reports it and reconnects' do
        expect do
          client.start
          wait_until { events.any? }
        end.to output(/Net::HTTPBadResponse/).to_stderr

        expect(events.first[:type]).to eq('features')
      end
    end

    context 'when the handler stops the client' do
      let(:handler) { ->(_event) { client.stop } }

      it 'stops without an error' do
        expect do
          client.start
          wait_until { !client.running? }
        end.not_to output.to_stderr

        expect(client.running?).to be(false)
      end
    end

    context 'when waiting a long time to reconnect' do
      let(:responses) { [[503]] }
      let(:reconnect_delay) { 30 }

      it 'stops at once' do
        client.start
        sleep 0.1

        started = Time.now
        client.stop
        expect(Time.now - started).to be < 1
      end
    end
  end
end
