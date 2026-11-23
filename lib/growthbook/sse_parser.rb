# frozen_string_literal: true

module Growthbook
  # Parses a Server-Sent Events stream into events.
  #
  # Lines may end with "\n" or "\r\n"; a lone "\r" line ending is not supported.
  class SSEParser
    def initialize
      @buffer = +''
      @event_type = nil
      @data = []
    end

    # Feeds the next chunk of the stream and yields every event it completes.
    #
    # @param chunk [String] Raw text from the stream, possibly cut mid-line
    # @yieldparam event [Hash] { type: String, data: String }
    def feed(chunk)
      @buffer << chunk
      while (index = @buffer.index("\n"))
        line = @buffer.slice!(0..index).chomp
        event = process_line(line)
        yield event if event
      end
    end

    # Yields the event still being built when the stream closes without a
    # trailing empty line.
    #
    # @yieldparam event [Hash] { type: String, data: String }
    def finish
      unless @buffer.empty?
        process_line(@buffer.chomp)
        @buffer = +''
      end

      event = dispatch
      yield event if event
    end

    private

    # @return [Hash, nil] The finished event, or nil if the line did not finish one
    def process_line(line)
      return dispatch if line.empty?
      return nil if line.start_with?(':')

      field, value = line.split(':', 2)
      value = (value || '').delete_prefix(' ')

      case field
      when 'event'
        @event_type = value
      when 'data'
        @data << value
      end

      nil
    end

    # Builds the event from the collected lines and resets for the next one.
    # An event without an "event:" line is dropped, as in the Python SDK.
    def dispatch
      type = @event_type
      data = @data.join("\n")
      @event_type = nil
      @data = []
      return nil if type.nil?

      { type: type, data: data }
    end
  end
end
