module Growthbook
  class Experiment
    attr_accessor :id
    attr_accessor :variations
    attr_accessor :coverage
    attr_accessor :weights
    attr_accessor :anon
    attr_accessor :targeting
    attr_accessor :data

    def initialize(id, variations, options = {})
      @id = id
      @variations = variations
      @coverage = options[:coverage] || 1
      @weights = options[:weights] || getEqualWeights()
      @anon = options.key?(:anon) ? options[:anon] : false
      @targeting = options[:targeting] || []
      @data = options[:data] || []
    end

    def getScaledWeights
      scaled = @weights.map do |n|
        n*@coverage
      end

      return scaled
    end

    private

    def getEqualWeights
      weights = []
      n = @variations
      for i in 1..n
        weights << (1.0 / n)
      end
      return weights
    end
  end
end