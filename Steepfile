# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature 'sig'

  check 'lib'
  check 'Gemfile'

  library 'base64', 'uri', 'json', 'openssl', 'bigdecimal'

  configure_code_diagnostics(D::Ruby.strict)

  configure_code_diagnostics do |hash|
    hash[D::Ruby::NoMethod] = :information
    hash[D::Ruby::FallbackAny] = :information
  end
end
