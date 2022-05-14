# frozen_string_literal: true

module Growthbook
  class Feature
    # @return [Any , nil]
    attr_reader :default_value

    # @return [Array<GrowthBook.FeatureRule>]
    attr_reader :rules

    def initialize(feature)
      @default_value = feature.key?('defaultValue') ? feature['defaultValue'] : nil

      @rules = []
      feature['rules'].each | rule | @rules[] = GrowthBook.FeatureRule.new(rule) if feature.key?('rules')
    end
  end
end
