# frozen_string_literal: true

require 'growthbook'

describe 'user' do
  describe '.experiment' do
    it 'uses experiment overrides in client first' do
      client = Growthbook::Client.new
      override = Growthbook::Experiment.new('my-test', 2)
      client.experiments << override

      experiment = Growthbook::Experiment.new('my-test', 2)
      user = client.user(id: '1')
      result = user.experiment(experiment)

      expect(result.experiment).to eq(override)
    end

    it 'assigns properly with both user id and anonymous ids' do
      client = Growthbook::Client.new
      user_only = client.user(id: '1')
      anon_only = client.user(anon_id: '2')
      both = client.user(id: '1', anon_id: '2')

      experiment_anon = Growthbook::Experiment.new('my-test', 2, anon: true)
      experiment_user = Growthbook::Experiment.new('my-test', 2, anon: false)

      expect(user_only.experiment(experiment_user).variation).to eq(1)
      expect(both.experiment(experiment_user).variation).to eq(1)
      expect(anon_only.experiment(experiment_user).variation).to eq(-1)

      expect(user_only.experiment(experiment_anon).variation).to eq(-1)
      expect(both.experiment(experiment_anon).variation).to eq(0)
      expect(anon_only.experiment(experiment_anon).variation).to eq(0)
    end

    it 'returns variation config data' do
      client = Growthbook::Client.new
      user = client.user(id: '1')
      experiment = Growthbook::Experiment.new(
        'my-test', 2, data: {
          color: %w[blue green],
          size: %w[small large]
        }
      )

      # Get correct config data
      result = user.experiment(experiment)
      expect(result.data[:color]).to eq('green')
      expect(result.data[:size]).to eq('large')

      # Fallback to control config data if not in test
      experiment.coverage = 0.01
      result = user.experiment(experiment)
      expect(result.data[:color]).to eq('blue')
      expect(result.data[:size]).to eq('small')

      # Null for undefined keys
      expect(result.data[:unknown]).to be_nil
    end

    it 'uses forced variations properly' do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new('my-test', 2, force: -1)
      user = client.user(id: '1')

      expect(user.experiment(experiment).variation).to eq(-1)
      experiment.force = 0
      expect(user.experiment(experiment).variation).to eq(0)
      experiment.force = 1
      expect(user.experiment(experiment).variation).to eq(1)
    end

    it 'evaluates targeting before forced variation' do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new('my-test', 2, force: 1, targeting: ['age > 18'])
      user = client.user(id: '1')

      expect(user.experiment(experiment).variation).to eq(-1)
    end

    it 'sets the shouldTrack flag on results' do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new('my-test', 2, data: { 'color' => %w[blue green] })
      client.experiments << experiment
      user = client.user(id: '1')

      # Normal
      expect(user.experiment('my-test').shouldTrack?).to be(true)
      expect(user.experiment('my-test').forced?).to be(false)
      expect(user.look_up_by_data_key('color').should_track?).to be(true)
      expect(user.look_up_by_data_key('color').forced?).to be(false)

      # Failed coverage
      experiment.coverage = 0.01
      expect(user.experiment('my-test').shouldTrack?).to be(false)
      expect(user.experiment('my-test').forced?).to be(false)
      expect(user.look_up_by_data_key('color')).to be_nil

      # Forced variation
      experiment.coverage = 1.0
      experiment.force = 1
      expect(user.experiment('my-test').shouldTrack?).to be(false)
      expect(user.experiment('my-test').forced?).to be(true)
      expect(user.look_up_by_data_key('color').should_track?).to be(false)
      expect(user.look_up_by_data_key('color').forced?).to be(true)
    end

    it 'can target an experiment given rules and attributes' do
      client = Growthbook::Client.new
      experiment = Growthbook::Experiment.new(
        'my-test', 2, targeting: [
          'member = true',
          'age > 18',
          'source ~ (google|yahoo)',
          'name != matt',
          'email !~ ^.*@exclude.com$'
        ]
      )

      attributes = {
        member: true,
        age: 21,
        source: 'yahoo',
        name: 'george',
        email: 'test@example.com'
      }

      # Matches all
      user = client.user(id: '1', attributes: attributes)
      expect(user.experiment(experiment).variation).to eq(1)

      # Missing negative checks
      user.attributes = {
        member: true,
        age: 21,
        source: 'yahoo'
      }
      expect(user.experiment(experiment).variation).to eq(1)

      # Fails boolean
      user.attributes = attributes.merge(
        {
          member: false
        }
      )
      expect(user.experiment(experiment).variation).to eq(-1)
    end
  end

  describe 'resultsToTrack' do
    it 'queues up results' do
      client = Growthbook::Client.new
      user = client.user(id: '1')

      user.experiment(Growthbook::Experiment.new('my-test', 2))
      user.experiment(Growthbook::Experiment.new('my-test2', 2))
      user.experiment(Growthbook::Experiment.new('my-test3', 2))

      expect(user.results_to_track.length).to eq(3)
    end

    it 'ignores duplicates' do
      client = Growthbook::Client.new
      user = client.user(id: '1')
      user.experiment(Growthbook::Experiment.new('my-test', 2))
      user.experiment(Growthbook::Experiment.new('my-test', 2))

      expect(user.results_to_track.length).to eq(1)
    end
  end

  describe '.lookupByDataKey' do
    let(:client) do
      c = Growthbook::Client.new
      c.experiments << Growthbook::Experiment.new(
        'button-color-size-chrome',
        2,
        targeting: ['browser = chrome'],
        data: {
          'button.color' => %w[blue green],
          'button.size'  => %w[small large]
        }
      )
      c.experiments << Growthbook::Experiment.new(
        'button-color-safari',
        2,
        targeting: ['browser = safari'],
        data: {
          'button.color' => %w[blue green]
        }
      )
      c
    end

    it 'returns nil when there are no matches' do
      user = client.user(id: '1')

      # No matches
      expect(user.look_up_by_data_key('button.unknown')).to be_nil
    end

    it 'returns the first matching experiment' do
      user = client.user(id: '1', attributes: { browser: 'chrome' })

      color = user.look_up_by_data_key('button.color')
      expect(color.value).to eq('blue')
      expect(color.experiment.id).to eq('button-color-size-chrome')

      size = user.look_up_by_data_key('button.size')
      expect(size.value).to eq('small')
      expect(size.experiment.id).to eq('button-color-size-chrome')
    end

    it 'skips experiments that fail targeting rules' do
      user = client.user(id: '1', attributes: { browser: 'safari' })

      color = user.look_up_by_data_key('button.color')
      expect(color.value).to eq('blue')
      expect(color.experiment.id).to eq('button-color-safari')

      size = user.look_up_by_data_key('button.size')
      expect(size).to be_nil
    end
  end
end
