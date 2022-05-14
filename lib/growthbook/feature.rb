# frozen_string_literal: true

module Growthbook
  class Feature
    # @return [Any , nil]
    attr_reader :default_value

    # @return [Array<Growthbook::FeatureRule>]
    attr_reader :rules

    def initialize(feature)
      @default_value = feature.key?('defaultValue') ? feature['defaultValue'] : nil

      @rules = []
      if feature.key?('rules')
        feature['rules'].each do | rule | 
          @rules << Growthbook::FeatureRule.new(rule)
        end
      end
    end
  end
end
