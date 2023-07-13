# frozen_string_literal: true

module Growthbook
  # Extendable class that can be used as the feature usage callback
  class FeatureUsageCallback
    def on_feature_usage(_feature_key, _result); end
  end
end
