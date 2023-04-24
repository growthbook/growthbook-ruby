# frozen_string_literal: true

module Growthbook
  # internal use only. Utils for working with encrypted feature payloads.
  class DecryptionUtil
    # @return [String, nil] The decrypted payload, or nil if it fails to decrypt
    def self.decrypt(payload = '', key:)
      return nil unless payload.include?('.')

      parts = payload.split('.')
      return nil if parts.empty? && parts.length != 2

      iv = parts[0]
      decoded_iv = Base64.strict_decode64(iv)
      decoded_key = Base64.strict_decode64(key)

      cipher_text = parts[1]
      decoded_cipher_text = Base64.strict_decode64(cipher_text)

      cipher = OpenSSL::Cipher.new('aes-128-cbc')

      cipher.decrypt
      cipher.key = decoded_key
      cipher.iv = decoded_iv

      cipher.update(decoded_cipher_text) + cipher.final
    rescue StandardError
      nil
    end
  end
end
