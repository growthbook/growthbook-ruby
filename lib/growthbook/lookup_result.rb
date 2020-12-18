require 'growthbook/result'

class LookupResult < Growthbook::Result
  attr_accessor :key
  attr_accessor :value

  def self.fromResult(result, key)
    obj = self.new(result.experiment, result.variation)
    obj.key= key
    obj.value=obj.getData(key)

    return obj
  end
end