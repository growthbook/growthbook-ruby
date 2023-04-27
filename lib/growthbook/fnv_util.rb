# frozen_string_literal: true

require 'base64'
require 'openssl'

module Growthbook
  # Utils for working with Fowler-Noll-Vo algorithm.
  class FNVUtil
    INIT32  = 0x811c9dc5
    PRIME32 = 0x01000193
    MOD32   = 2**32

    # @return [String] The hashed data using the fnv32a algorithm.
    def self.fnv1a_32(data) # rubocop:disable Naming/VariableNumber
      hash = INIT32

      data.bytes.each do |byte|
        hash = hash ^ byte
        hash = (hash * PRIME32) % MOD32
      end

      hash
    end
  end
end
