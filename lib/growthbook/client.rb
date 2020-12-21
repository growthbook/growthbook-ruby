module Growthbook
  class Client
    # @returns [Boolean]
    attr_accessor :enabled
    
    # @returns [Array<Growthbook::Experiment>]
    attr_accessor :experiments

    # @param config [Hash]
    # @option config [Boolean] :enabled (true) Set to false to disable all experiments
    # @option config [Array<Growthbook::Experiment>] :experiments ([]) Array of Growthbook::Experiment objects
    def initialize(config = {})
      @enabled = config.has_key?(:enabled) ? config[:enabled] : true
      @experiments = config[:experiments] || []
    end

    # Look up a pre-configured experiment by id
    # 
    # @param id [String] The experiment id to look up
    # @return [Growthbook::Experiment, nil] the experiment object or nil if not found
    def getExperiment(id)
      match = nil;
      @experiments.each do |exp|
        if exp.id == id
          match = exp
          break
        end
      end
      return match
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
        params[:anonId] || nil,
        params[:id] || nil,
        params[:attributes] || nil,
        self
      )
    end
  end
end