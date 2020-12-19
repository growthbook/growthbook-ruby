require 'growthbook'

describe 'growthbook' do

  def chooseVariation(user, experiment)
    if user.is_a? String
      user = @client.user(id: user)
    end
    return user.experiment(experiment).variation
  end

  before(:all) do
    @client = Growthbook::Client.new
  end

  before(:each) do
    @client.enabled = true
    @client.experiments = []
  end

  describe "experiments" do
    it "default weights" do
      experiment = Growthbook::Experiment.new("my-test", 2)

      expect(chooseVariation('1', experiment)).to eq(1)
      expect(chooseVariation('2', experiment)).to eq(0)
      expect(chooseVariation('3', experiment)).to eq(0)
      expect(chooseVariation('4', experiment)).to eq(1)
      expect(chooseVariation('5', experiment)).to eq(1)
      expect(chooseVariation('6', experiment)).to eq(1)
      expect(chooseVariation('7', experiment)).to eq(0)
      expect(chooseVariation('8', experiment)).to eq(1)
      expect(chooseVariation('9', experiment)).to eq(0)
    end

    it "uneven weights" do
      experiment = Growthbook::Experiment.new("my-test", 2, weights: [0.1, 0.9])

      expect(chooseVariation('1', experiment)).to eq(1)
      expect(chooseVariation('2', experiment)).to eq(1)
      expect(chooseVariation('3', experiment)).to eq(0)
      expect(chooseVariation('4', experiment)).to eq(1)
      expect(chooseVariation('5', experiment)).to eq(1)
      expect(chooseVariation('6', experiment)).to eq(1)
      expect(chooseVariation('7', experiment)).to eq(0)
      expect(chooseVariation('8', experiment)).to eq(1)
      expect(chooseVariation('9', experiment)).to eq(1)
    end

    it "coverage" do
      experiment = Growthbook::Experiment.new("my-test", 2, coverage: 0.4)

      expect(chooseVariation('1', experiment)).to eq(-1)
      expect(chooseVariation('2', experiment)).to eq(0)
      expect(chooseVariation('3', experiment)).to eq(0)
      expect(chooseVariation('4', experiment)).to eq(-1)
      expect(chooseVariation('5', experiment)).to eq(-1)
      expect(chooseVariation('6', experiment)).to eq(-1)
      expect(chooseVariation('7', experiment)).to eq(0)
      expect(chooseVariation('8', experiment)).to eq(-1)
      expect(chooseVariation('9', experiment)).to eq(1)
    end

    it "3-way tests" do
      experiment = Growthbook::Experiment.new("my-test", 3)

      expect(chooseVariation('1', experiment)).to eq(2)
      expect(chooseVariation('2', experiment)).to eq(0)
      expect(chooseVariation('3', experiment)).to eq(0)
      expect(chooseVariation('4', experiment)).to eq(2)
      expect(chooseVariation('5', experiment)).to eq(1)
      expect(chooseVariation('6', experiment)).to eq(2)
      expect(chooseVariation('7', experiment)).to eq(0)
      expect(chooseVariation('8', experiment)).to eq(1)
      expect(chooseVariation('9', experiment)).to eq(0)
    end

    it "experiment name" do
      experiment1 = Growthbook::Experiment.new("my-test", 2)
      experiment2 = Growthbook::Experiment.new("my-test-3", 2)

      expect(chooseVariation('1', experiment1)).to eq(1)
      expect(chooseVariation('1', experiment2)).to eq(0)
    end

    it "anonId" do
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

    it "test override" do
      override = Growthbook::Experiment.new("my-test", 2)
      @client.experiments << override

      experiment = Growthbook::Experiment.new("my-test", 2)
      user = @client.user(id: "1")
      result = user.experiment(experiment)

      expect(result.experiment).to eq(override)
    end

    it "targeting" do
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

      user = @client.user(id: "1", attributes: attributes)
      expect(chooseVariation(user, experiment)).to eq(1)
    end
  end
end