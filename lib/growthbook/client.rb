module Growthbook
  class Client
    attr_accessor :config
    attr_accessor :experiments

    def initialize(config = nil)
      @config = config || Growthbook::Config.new
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
        params[:anonId] || "",
        params[:id] || "",
        params[:attributes] || [],
        self
      )
    end
  end
end