# frozen_string_literal: true

module Growthbook
  # Extendable class that can be used as the tracking callback
  class TrackingCallback
    def on_experiment_viewed(_experiment, _result); end
  end
end
