require 'growthbook'
require 'json'

describe 'context' do
  describe "feature helper methods" do
    gb = Growthbook::Context.new(
      features: {
        feature1: {
          defaultValue: 1
        },
        feature2: {
          defaultValue: 0
        }
      }
    )

    it ".on?" do
      expect(gb.on?(:feature1)).to eq(true)
      expect(gb.on?(:feature2)).to eq(false)
    end
    it ".off?" do
      expect(gb.off?(:feature1)).to eq(false)
      expect(gb.off?(:feature2)).to eq(true)
    end
    it ".feature_value" do
      expect(gb.feature_value(:feature1)).to eq(1)
      expect(gb.feature_value(:feature2)).to eq(0)
    end
  end

  describe "forced feature values" do
    it "uses forced values" do
      gb = Growthbook::Context.new(
        features: {
          feature: {
            defaultValue: "a"
          },
          feature2: {
            defaultValue: true
          }
        }
      )

      gb.forced_features = {
        feature: "b",
        another: 2
      }

      expect(gb.feature_value(:feature)).to eq("b")
      expect(gb.feature_value(:feature2)).to eq(true)
      expect(gb.feature_value(:another)).to eq(2)
      expect(gb.feature_value(:unknown)).to eq(nil)
    end
  end

  describe "tracking" do
    it "queues up impressions" do
      class MyImpressionListener
        attr_accessor :tracked
        def on_experiment_viewed(exp, res)
          @tracked = [exp.to_json, res.to_json]
        end
      end

      listener = MyImpressionListener.new

      gb = Growthbook::Context.new(
        attributes: {
          id: "123"
        },
        features: {
          feature1: {
            defaultValue: 1,
            rules: [
              {
                variations: [2, 3]
              }
            ]
          },
          feature2: {
            defaultValue: 0,
            rules: [
              {
                variations: [4, 5]
              }
            ]
          }
        },
        listener: listener
      )

      expect(gb.impressions).to eq({})
      expect(listener.tracked).to eq(nil)

      gb.on? :feature1

      expect(gb.impressions["feature1"].to_json).to eq({
        "hashAttribute" => "id",
        "hashValue" => "123",
        "inExperiment" => true,
        "value" => 2,
        "variationId" => 0,
      })

      expect(listener.tracked).to eq([
        {
          "key" => "feature1",
          "variations" => [2, 3]
        },
        {
          "hashAttribute" => "id",
          "hashValue" => "123",
          "inExperiment" => true,
          "value" => 2,
          "variationId" => 0,
        }
      ])
    end
  end
end