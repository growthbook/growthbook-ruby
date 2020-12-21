require 'growthbook'
require 'json'

describe 'client' do
  describe ".enabled" do
    it "chooses variation -1 when client is disabled" do
      client = Growthbook::Client.new(enabled: false)
      user = client.user(id: "1")
      experiment = Growthbook::Experiment.new("my-test", 2)
      expect(user.experiment(experiment).variation).to eq(-1)
    end
  end
  describe ".importExperimentsHash" do
    it("imports correctly") do
      client = Growthbook::Client.new

      # Example JSON response from the GrowthBook API
      json = '{
        "status": 200,
        "experiments": {
          "my-test": {
            "variations": 2,
            "coverage": 0.6,
            "weights": [0.8, 0.2],
            "anon": true,
            "force": 1,
            "targeting": [
              "source = google"
            ],
            "data": {
              "color": ["blue", "green"]
            }
          },
          "my-stopped-test": {
            "variations": 3,
            "force": 1
          }
        }
      }'

      parsed = JSON.parse(json)
      client.importExperimentsHash(parsed["experiments"])

      expect(client.experiments.length).to eq(2)

      experiment = client.experiments[0]
      expect(experiment.id).to eq("my-test")
      expect(experiment.variations).to eq(2)
      expect(experiment.coverage).to eq(0.6)
      expect(experiment.weights[0]).to eq(0.8)
      expect(experiment.anon).to eq(true)
      expect(experiment.force).to eq(1)
      expect(experiment.targeting[0]).to eq("source = google")
      expect(experiment.data["color"][0]).to eq("blue")
    end
  end
end