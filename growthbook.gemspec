# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name          = 'growthbook'
  s.version       = '0.3.0'
  s.summary       = 'GrowthBook SDK for Ruby'
  s.description   = 'Official GrowthBook SDK for Ruby'
  s.authors       = ['GrowthBook']
  s.email         = 'jeremy@growthbook.io'
  s.homepage      = 'https://github.com/growthbook/growthbook-ruby'
  s.files         = Dir.glob("lib/**/*")
  s.test_files    = Dir.glob("spec/**/*")
  s.license       = 'MIT'
  s.require_paths = ['lib']

  s.add_development_dependency 'rspec', '~> 3.2'
  s.add_development_dependency 'rubocop', '~> 1.50.2'

  s.add_runtime_dependency 'fnv', '~> 0.2.0'
end
