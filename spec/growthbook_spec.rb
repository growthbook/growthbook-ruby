require 'growthbook'

describe 'growthbook' do
  # Small helper function to run an experiment and return the variation
  def chooseVariation(user, experiment)
    if user.is_a? String
      user = @client.user(id: user)
    end
    return user.experiment(experiment)[:variation]
  end

  before(:all) do
    @client = Growthbook::Client.new
  end

  before(:each) do
    # Reset the client
    @client.enabled = true
    @client.experiments = []
  end

  describe "experiments" do
    it "assigns properly with both user id and anonymous ids" do
      userOnly = @client.user(id: "1")
      anonOnly = @client.user(anonId: "2")
      both = @client.user(id: "1", anonId: "2")

      experimentAnon = Growthbook::Experiment.new("my-test", 2, anon:true)
      experimentUser = Growthbook::Experiment.new("my-test", 2, anon:false)

      expect(chooseVariation(userOnly, experimentUser)).to eq(1)
      expect(chooseVariation(both, experimentUser)).to eq(1)
      expect(chooseVariation(anonOnly, experimentUser)).to eq(-1)

      expect(chooseVariation(userOnly, experimentAnon)).to eq(-1)
      expect(chooseVariation(both, experimentAnon)).to eq(0)
      expect(chooseVariation(anonOnly, experimentAnon)).to eq(0)
    end

    it "uses experiment overrides in client first" do
      override = Growthbook::Experiment.new("my-test", 2)
      @client.experiments << override

      experiment = Growthbook::Experiment.new("my-test", 2)
      user = @client.user(id: "1")
      result = user.experiment(experiment)

      expect(result[:experiment]).to eq(override)
    end

    it "chooses variation -1 when client is disabled" do
      @client.enabled = false
      experiment = Growthbook::Experiment.new("my-test", 2)
      expect(chooseVariation("1", experiment)).to eq(-1)
    end

    it "returns variation config data" do
      user = @client.user(id: "1")
      experiment = Growthbook::Experiment.new("my-test", 2, data: {
        :color => ["blue", "green"],
        :size => ["small", "large"]
      })

      # Get correct config data
      result = user.experiment(experiment)
      expect(result[:data][:color]).to eq("green")
      expect(result[:data][:size]).to eq("large")

      # Fallback to control config data if not in test
      experiment.coverage = 0.01
      result = user.experiment(experiment)
      expect(result[:data][:color]).to eq("blue")
      expect(result[:data][:size]).to eq("small")

      # Null for undefined keys
      expect(result[:data][:unknown]).to eq(nil)
    end

    it "can lookup by config data key" do
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

      user = @client.user(id: "1")

      # No matches
      expect(user.lookupByDataKey("button.unknown")).to eq(nil)

      # First matching experiment
      user.attributes = {:browser => "chrome"}
      color = user.lookupByDataKey("button.color")
      size = user.lookupByDataKey("button.size")
      expect(color[:value]).to eq("blue")
      expect(color[:experiment].id).to eq("button-color-size-chrome")
      expect(size[:value]).to eq("small")
      expect(size[:experiment].id).to eq("button-color-size-chrome")

      # Fallback experiment
      user.attributes = {:browser => "safari"}
      color = user.lookupByDataKey("button.color")
      size = user.lookupByDataKey("button.size")
      expect(color[:value]).to eq("blue")
      expect(color[:experiment].id).to eq("button-color-safari")
      expect(size).to eq(nil)
    end

    it "can target an experiment given rules and attributes" do
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
      user = @client.user(id: "1", attributes: attributes)
      expect(chooseVariation(user, experiment)).to eq(1)

      # Missing negative checks
      user.attributes={
        :member => true,
        :age => 21,
        :source => "yahoo"
      }
      expect(chooseVariation(user, experiment)).to eq(1)

      # Fails boolean
      user.attributes=attributes.merge({
        :member => false
      })
      expect(chooseVariation(user, experiment)).to eq(-1)

      # Fails number
      user.attributes=attributes.merge({
        :age => 17
      })
      expect(chooseVariation(user, experiment)).to eq(-1)

      # Fails regex
      user.attributes=attributes.merge({
        :source => "goog"
      })
      expect(chooseVariation(user, experiment)).to eq(-1)

      # Fails not equals
      user.attributes=attributes.merge({
        :name => "matt"
      })
      expect(chooseVariation(user, experiment)).to eq(-1)

      # Fails not regex
      user.attributes=attributes.merge({
        :email => "test@exclude.com"
      })
      expect(chooseVariation(user, experiment)).to eq(-1)
    end
  end
end