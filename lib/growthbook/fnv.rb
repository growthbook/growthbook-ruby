# frozen_string_literal: true

# FNV
# {https://github.com/jakedouglas/fnv-ruby Source}
class FNV
  INIT32  = 0x811c9dc5
  INIT64  = 0xcbf29ce484222325
  PRIME32 = 0x01000193
  PRIME64 = 0x100000001b3
  MOD32   = 4_294_967_296
  MOD64   = 18_446_744_073_709_551_616

  # Hashes UTF-16 code units, like JavaScript's charCodeAt, so a character
  # above U+FFFF counts as two units
  def fnv1a_32(data)
    hash = INIT32

    units = data.ascii_only? ? data.bytes : data.encode('UTF-16LE').unpack('v*').map(&:to_i)
    units.each do |unit|
      hash = hash ^ unit
      hash = (hash * PRIME32) % MOD32
    end

    hash
  end
end
