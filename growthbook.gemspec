# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name          = 'growthbook'
  s.version       = '1.0.0'
  s.summary       = 'GrowthBook SDK for Ruby'
  s.description   = 'Official GrowthBook SDK for Ruby'
  s.authors       = ['GrowthBook']
  s.email         = 'jeremy@growthbook.io'
  s.homepage      = 'https://github.com/growthbook/growthbook-ruby'
  s.files         = Dir.glob('lib/**/*')
  s.license       = 'MIT'
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 2.5.0'

  s.add_development_dependency 'rspec', '~> 3.2'
  s.add_development_dependency 'simplecov', '~> 0.21'
  s.add_development_dependency 'simplecov-shields-badge', '~> 0.1.0'

  s.metadata['rubygems_mfa_required'] = 'true'
end
