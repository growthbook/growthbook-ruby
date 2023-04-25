# frozen_string_literal: true

# D = Steep::Diagnostic
#
target :lib do
  signature 'sig'

  check 'lib'

  # check "Gemfile"                   # File name

  # ignore "spec/**/*.rb"

  library 'uri', 'json', 'openssl', 'bigdecimal'
  # library "pathname", "set"       # Standard libraries
  # library "strong_json"           # Gems

  # configure_code_diagnostics(D::Ruby.strict)       # `strict` diagnostics setting
  # configure_code_diagnostics(D::Ruby.lenient)      # `lenient` diagnostics setting
  # configure_code_diagnostics do |hash|             # You can setup everything yourself
  #   hash[D::Ruby::NoMethod] = :information
  # end
end

# target :test do
#   signature "sig", "sig-private"
#
#   check "spec"
#
#   # library "pathname", "set"       # Standard libraries
# end
