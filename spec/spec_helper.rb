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

RSpec.configure do |config|
  # The default feature cache is shared for the whole process, so without this a
  # payload fetched by one example is served to the next one
  config.before do
    Growthbook::FeatureRepository.default_cache.clear
  end
end
