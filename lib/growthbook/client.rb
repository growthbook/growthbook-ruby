require 'growthbook/config'
require 'growthbook/user'

class Growthbook::Client
  attr_accessor :config
  attr_accessor :experiments

  def initialize(config)
    @config = config || Growthbook::Config.new
    @experiments = []
  end

  def getExperiment(id)
    @experiments.each do |exp|
      return exp if exp.id == id
    end
  end

  def user(params = {})
    Growthbook::User.new(
      params.anonId || "",
      params.id || "",
      params.attributes || [],
      self
    )
  end
end