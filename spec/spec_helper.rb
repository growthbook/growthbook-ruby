# frozen_string_literal: true

require 'simplecov'
require 'shields_badge'

SimpleCov.start do
  add_filter %r{^/spec/}
end
SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::ShieldsBadge
  ]
)
