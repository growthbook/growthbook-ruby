module Growthbook
  class Client
    attr_accessor :enabled
    attr_accessor :experiments

    def initialize(config = {})
      @enabled = config.key?(:enabled) ? config[:enabled] : true
      @experiments = []
    end

    def getExperiment(id)
      match = nil;
      @experiments.each do |exp|
        if exp.id == id
          match = exp
        end
      end
      return match
    end

    def user(params = {})
      Growthbook::User.new(
        params[:anonId] || nil,
        params[:id] || nil,
        params[:attributes] || [],
        self
      )
    end
  end
end