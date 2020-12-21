require 'growthbook'

describe 'client' do
  describe ".enabled" do
    it "chooses variation -1 when client is disabled" do
      client = Growthbook::Client.new(enabled: false)
      user = client.user(id: "1")
      experiment = Growthbook::Experiment.new("my-test", 2)
      expect(user.experiment(experiment).variation).to eq(-1)
    end
  end
end