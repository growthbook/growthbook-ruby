# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

RSpec.describe Growthbook::RemoteEvalCache do
  subject(:cache) { described_class.new }

  it 'caches nothing until it is subclassed' do
    cache.set('a', 'value', 60)

    expect(cache.get('a')).to be_nil
  end
end
