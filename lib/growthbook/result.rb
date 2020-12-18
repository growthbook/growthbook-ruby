class Result
  attr_accessor :experiment
  attr_accessor :variation

  def initialize(experiment = nil, variation = -1)
    @experiment = experiment
    @variation = variation
  end

  def getData(key)
    return nil if !@experiment
    return nil if !@experiment.data.key?(key)

    data = @experiment.data[key]
    return data[0] if @variation >= data.len

    return data[@variation]
  end
end