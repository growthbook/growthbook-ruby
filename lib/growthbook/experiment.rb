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
    @coverage = options['coverage'] || 1
    @weights = options['weights'] || getEqualWeights()
    @anon = options['anon'] || false
    @targeting = options['targeting'] || []
    @data = options['data'] || []
  end

  def getScaledWeights
    @weights.map do [n]
      n*@coverage
    end
  end

  private

  def getEqualWeights
    weights = []
    for i in 0..@variations
      weights << 1 / @variations
    end
    return weights
  end
end