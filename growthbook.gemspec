# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name          = 'growthbook'
  s.version       = '1.3.0'
  s.summary       = 'GrowthBook SDK for Ruby'
  s.description   = 'Official GrowthBook SDK for Ruby'
  s.authors       = ['GrowthBook']
  s.email         = 'jeremy@growthbook.io'
  s.homepage      = 'https://github.com/growthbook/growthbook-ruby'
  s.files         = Dir.glob('lib/**/*')
  s.license       = 'MIT'
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 2.5.0'

  # base64 and bigdecimal are no longer default gems starting from Ruby 3.4, so declare them explicitly
  s.add_dependency 'base64'
  s.add_dependency 'bigdecimal'

  # rbs is pinned to 3.4.x: steep 1.6.0 hangs on rbs 3.6+ (UntypedFunction)
  s.add_development_dependency 'rbs', '~> 3.4.0'
  s.add_development_dependency 'rspec', '~> 3.2'
  s.add_development_dependency 'rspec-its', '~> 1.3'
  s.add_development_dependency 'simplecov', '~> 0.21'
  s.add_development_dependency 'simplecov-shields-badge', '~> 0.1.0'
  s.add_development_dependency 'steep', '~> 1.6.0'
  s.add_development_dependency 'webmock', '~> 3.18'

  s.metadata['rubygems_mfa_required'] = 'true'
end
