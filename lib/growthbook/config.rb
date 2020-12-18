class Config
  attr_accessor :enabled

  def initialize(options = {})
    @enabled = options['enabled'] || true
  end
end