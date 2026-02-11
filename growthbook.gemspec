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

  s.add_dependency 'base64', '~> 0.3.0'

  s.metadata['rubygems_mfa_required'] = 'true'
end
