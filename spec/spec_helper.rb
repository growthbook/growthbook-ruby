# frozen_string_literal: true

require 'rspec/its'
require 'simplecov'
require 'shields_badge'
require 'webmock/rspec'

WebMock.disable_net_connect!

SimpleCov.start do
  add_filter %r{^/spec/}
end
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::ShieldsBadge
  ]
)
