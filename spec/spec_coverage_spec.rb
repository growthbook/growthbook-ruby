# frozen_string_literal: true

require 'spec_helper'
require 'json'

# Every section of the shared spec (spec/cases.json) is either run by a test or
# excluded here with a reason, so a new section in a spec update can't be
# skipped without anyone noticing. json_spec.rb reads each section by name and
# ignores the ones it doesn't ask for. Nested sections are listed as `parent.child`.
describe 'spec coverage' do
  # Sections the tests run, and the file that runs each one
  run_sections = {
    'evalCondition'                        => 'json_spec.rb',
    'pruneCondition'                       => 'json_spec.rb',
    'reducePayload'                        => 'json_spec.rb',
    'hash'                                 => 'json_spec.rb',
    'getBucketRange'                       => 'json_spec.rb',
    'feature'                              => 'json_spec.rb',
    'run'                                  => 'json_spec.rb',
    'chooseVariation'                      => 'json_spec.rb',
    'getQueryStringOverride'               => 'json_spec.rb',
    'inNamespace'                          => 'json_spec.rb',
    'getEqualWeights'                      => 'json_spec.rb',
    'decrypt'                              => 'json_spec.rb',
    'stickyBucket'                         => 'json_spec.rb',
    'savedGroupReferencesV2.evalCondition' => 'json_spec.rb',
    'savedGroupReferencesV2.feature'       => 'json_spec.rb',
    'savedGroupReferencesV2.run'           => 'json_spec.rb'
  }

  # Sections the tests don't run, and why
  excluded_sections = {
    'urlRedirect'                              => 'URL redirect experiments are a browser feature',
    'contextualBandit'                         => "Contextual bandits aren't implemented",
    'savedGroupReferencesRemote.evalCondition' => "Remote saved groups aren't implemented yet",
    'savedGroupReferencesRemote.feature'       => "Remote saved groups aren't implemented yet"
  }

  spec_sections = JSON.parse(File.read(File.join(__dir__, 'cases.json'))).flat_map do |name, value|
    case value
    when Array then [name]
    when Hash then value.keys.map { |child| "#{name}.#{child}" }
    else [] # specVersion
    end
  end

  it 'runs every spec section or excludes it with a reason' do
    expect(spec_sections - run_sections.keys - excluded_sections.keys).to be_empty
  end

  it 'lists only sections that are in the spec' do
    expect(run_sections.keys + excluded_sections.keys - spec_sections).to be_empty
  end

  it 'does not both run and exclude a section' do
    expect(run_sections.keys & excluded_sections.keys).to be_empty
  end

  it 'gives every excluded section a reason' do
    expect(excluded_sections.values.map(&:strip)).to all(satisfy { |reason| !reason.empty? })
  end
end
