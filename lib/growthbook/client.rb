# frozen_string_literal: true

module Growthbook
  # @deprecated
  # internal use only
  class Client
    # @return [Boolean]
    attr_accessor :enabled

    # @return [Array<Growthbook::Experiment>]
    attr_accessor :experiments

    # @param config [Hash]
    # @option config [Boolean] :enabled (true) Set to false to disable all experiments
    # @option config [Array<Growthbook::Experiment>] :experiments ([]) Array of Growthbook::Experiment objects
    def initialize(config = {})
      @enabled = config.key?(:enabled) ? config[:enabled] : true
      @experiments = config[:experiments] || []
      @results_to_track = []
    end

    # Look up a pre-configured experiment by id
    #
    # @param id [String] The experiment id to look up
    # @return [Growthbook::Experiment, nil] the experiment object or nil if not found
    def get_experiment(id)
      match = nil
      @experiments.each do |exp|
        if exp.id == id
          match = exp
          break
        end
      end
      match
    end

    # Get a User object you can run experiments against
    #
    # @param params [Hash]
    # @option params [String, nil] :id The logged-in user id
    # @option params [String, nil] :anonId The anonymous id (session id, ip address, cookie, etc.)
    # @option params [Hash, nil] :attributes Any user attributes you want to use for experiment targeting
    #    Values can be any type, even nested arrays and hashes
    # @return [Growthbook::User] the User object
    def user(params = {})
      Growthbook::User.new(
        params[:anon_id] || nil,
        params[:id] || nil,
        params[:attributes] || nil,
        self
      )
    end

    def import_experiments_hash(experiments_hash = {})
      @experiments = []
      experiments_hash.each do |id, data|
        variations = data['variations']

        options = {}
        options[:coverage] = data['coverage'] if data.key?('coverage')
        options[:weights] = data['weights'] if data.key?('weights')
        options[:force] = data['force'] if data.key?('force')
        options[:anon] = data['anon'] if data.key?('anon')
        options[:targeting] = data['targeting'] if data.key?('targeting')
        options[:data] = data['data'] if data.key?('data')

        @experiments << Growthbook::Experiment.new(id, variations, options)
      end
    end
  end
end
