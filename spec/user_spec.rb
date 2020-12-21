require 'growthbook'

describe 'user' do
  describe ".experiment" do
    it "uses experiment overrides in client first" do
      client = Growthbook::Client.new
      override = Growthbook::Experiment.new("my-test", 2)
      client.experiments << override

      experiment = Growthbook::Experiment.new("my-test", 2)
      user = client.user(id: "1")
      result = user.experiment(experiment)

      expect(result.experiment).to eq(override)
    end

    it "assigns properly with both user id and anonymous ids" do
      client = Growthbook::Client.new
      userOnly = client.user(id: "1")
      anonOnly = client.user(anonId: "2")
      both = client.user(id: "1", anonId: "2")

      experimentAnon = Growthbook::Experiment.new("my-test", 2, anon:true)
      experimentUser = Growthbook::Experiment.new("my-test", 2, anon:false)

      expect(userOnly.experiment(experimentUser).variation).to eq(1)
      expect(both.experiment(experimentUser).variation).to eq(1)
      expect(anonOnly.experiment(experimentUser).variation).to eq(-1)

      expect(userOnly.experiment(experimentAnon).variation).to eq(-1)
      expect(both.experiment(experimentAnon).variation).to eq(0)
      expect(anonOnly.experiment(experimentAnon).variation).to eq(0)
    end

    it "returns variation config data" do
      client = Growthbook::Client.new
      user = client.user(id: "1")
      experiment = Growthbook::Experiment.new("my-test", 2, data: {
        :color => ["blue", "green"],
        :size => ["small", "large"]
      })

      # Get correct config data
      result = user.experiment(experiment)
      expect(result.data[:color]).to eq("green")
      expect(result.data[:size]).to eq("large")

      # Fallback to control config data if not in test
      experiment.coverage = 0.01
      result = user.experiment(experiment)
      expect(result.data[:color]).to eq("blue")
      expect(result.data[:size]).to eq("small")

      # Null for undefined keys
      expect(result.data[:unknown]).to eq(nil)
    end

    it "uses forced variations properly" do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new("my-test", 2, force: -1)
      user = client.user(id: "1")

      expect(user.experiment(experiment).variation).to eq(-1)
      experiment.force = 0
      expect(user.experiment(experiment).variation).to eq(0)
      experiment.force = 1
      expect(user.experiment(experiment).variation).to eq(1)
    end

    it "evaluates targeting before forced variation" do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new("my-test", 2, force: 1, targeting: ["age > 18"])
      user = client.user(id: "1")

      expect(user.experiment(experiment).variation).to eq(-1)
    end

    it "sets the shouldTrack flag on results" do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new("my-test", 2, data: {"color" => ["blue", "green"]})
      client.experiments << experiment
      user = client.user(id: "1")

      # Normal
      expect(user.experiment("my-test").shouldTrack?).to eq(true)
      expect(user.experiment("my-test").forced?).to eq(false)
      expect(user.lookupByDataKey("color").shouldTrack?).to eq(true)
      expect(user.lookupByDataKey("color").forced?).to eq(false)

      # Failed coverage
      experiment.coverage = 0.01
      expect(user.experiment("my-test").shouldTrack?).to eq(false)
      expect(user.experiment("my-test").forced?).to eq(false)
      expect(user.lookupByDataKey("color")).to eq(nil)

      # Forced variation
      experiment.coverage = 1.0
      experiment.force = 1
      expect(user.experiment("my-test").shouldTrack?).to eq(false)
      expect(user.experiment("my-test").forced?).to eq(true)
      expect(user.lookupByDataKey("color").shouldTrack?).to eq(false)
      expect(user.lookupByDataKey("color").forced?).to eq(true)
    end

    it "can target an experiment given rules and attributes" do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new("my-test", 2, targeting: [
        "member = true",
        "age > 18",
        "source ~ (google|yahoo)",
        "name != matt",
        "email !~ ^.*@exclude.com$"
      ])

      attributes = {
        :member => true,
        :age => 21,
        :source => 'yahoo',
        :name => 'george',
        :email => 'test@example.com'
      }

      # Matches all
      user = client.user(id: "1", attributes: attributes)
      expect(user.experiment(experiment).variation).to eq(1)

      # Missing negative checks
      user.attributes={
        :member => true,
        :age => 21,
        :source => "yahoo"
      }
      expect(user.experiment(experiment).variation).to eq(1)

      # Fails boolean
      user.attributes=attributes.merge({
        :member => false
      })
      expect(user.experiment(experiment).variation).to eq(-1)
    end
  end

  describe "resultsToTrack" do
    it "queues up results" do
      client = Growthbook::Client.new
      user = client.user(id: "1")

      user.experiment(Growthbook::Experiment.new("my-test", 2))
      user.experiment(Growthbook::Experiment.new("my-test2", 2))
      user.experiment(Growthbook::Experiment.new("my-test3", 2))

      expect(user.resultsToTrack.length).to eq(3)
    end
    it "ignores duplicates" do
      client = Growthbook::Client.new
      user = client.user(id: "1")
      user.experiment(Growthbook::Experiment.new("my-test", 2))
      user.experiment(Growthbook::Experiment.new("my-test", 2))

      expect(user.resultsToTrack.length).to eq(1)
    end
  end

  describe ".lookupByDataKey" do
    before(:all) do
      @client = Growthbook::Client.new
      @client.experiments << Growthbook::Experiment.new(
        "button-color-size-chrome", 
        2,
        :targeting => ["browser = chrome"],
        :data => {
          "button.color" => ["blue", "green"],
          "button.size" => ["small", "large"]
        }
      )
      @client.experiments <<  Growthbook::Experiment.new(
        "button-color-safari", 
        2,
        :targeting => ["browser = safari"],
        :data => {
          "button.color" => ["blue", "green"]
        }
      )
    end
    it "returns nil when there are no matches" do
      user = @client.user(id: "1")

      # No matches
      expect(user.lookupByDataKey("button.unknown")).to eq(nil)
    end
    it "returns the first matching experiment" do
      user = @client.user(id: "1", attributes: {:browser => "chrome"})

      color = user.lookupByDataKey("button.color")
      expect(color.value).to eq("blue")
      expect(color.experiment.id).to eq("button-color-size-chrome")

      size = user.lookupByDataKey("button.size")
      expect(size.value).to eq("small")
      expect(size.experiment.id).to eq("button-color-size-chrome")
    end
    it "skips experiments that fail targeting rules" do
      user = @client.user(id: "1", attributes: {:browser => "safari"})

      color = user.lookupByDataKey("button.color")
      expect(color.value).to eq("blue")
      expect(color.experiment.id).to eq("button-color-safari")

      size = user.lookupByDataKey("button.size")
      expect(size).to eq(nil)
    end
  end
end