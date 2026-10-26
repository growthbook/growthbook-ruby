# frozen_string_literal: true

require_relative '../spec_helper'
require 'growthbook'

describe Growthbook::Util do
  describe 'checkRule function' do
    it 'works for all operators and normal inputs' do
      # =
      expect(described_class.check_rule('test', '=', 'test')).to be(true)
      expect(described_class.check_rule('test', '=', 'other')).to be(false)
      # !=
      expect(described_class.check_rule('test', '!=', 'other')).to be(true)
      expect(described_class.check_rule('test', '!=', 'test')).to be(false)
      # >
      expect(described_class.check_rule('b', '>', 'a')).to be(true)
      expect(described_class.check_rule('a', '>', 'b')).to be(false)
      # <
      expect(described_class.check_rule('a', '<', 'b')).to be(true)
      expect(described_class.check_rule('b', '<', 'a')).to be(false)
      # ~
      expect(described_class.check_rule('123-456-abc', '~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(true)
      expect(described_class.check_rule('123-abc-456', '~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(false)
      # !~
      expect(described_class.check_rule('123-abc-456', '!~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(true)
      expect(described_class.check_rule('123-456-abc', '!~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(false)
    end

    it "returns true when there's an unknown operator" do
      expect(described_class.check_rule('abc', '*', '123')).to be(true)
    end

    it 'returns false when the regex is invalid' do
      expect(described_class.check_rule('abc', '~', 'abc)')).to be(false)
    end

    it 'compares numeric strings with natural ordering' do
      expect(described_class.check_rule('10', '>', '9')).to be(true)
      expect(described_class.check_rule('9', '<', '1000')).to be(true)
      expect(described_class.check_rule('90', '>', '800')).to be(false)
      expect(described_class.check_rule('-10', '<', '10')).to be(true)
      expect(described_class.check_rule('10', '>', 'abc')).to be(false)
    end

    it 'checks for numeric equality properly' do
      expect(described_class.check_rule('9.0', '=', '9')).to be(true)
      expect(described_class.check_rule('1.3', '!=', '1.30000')).to be(false)
    end

    it 'handles empty strings' do
      expect(described_class.check_rule('', '=', '')).to be(true)
      expect(described_class.check_rule('', '!=', '')).to be(false)
      expect(described_class.check_rule('', '>', '')).to be(false)
      expect(described_class.check_rule('', '<', '')).to be(false)
      expect(described_class.check_rule('', '~', '')).to be(true)
      expect(described_class.check_rule('', '!~', '')).to be(false)
    end
  end

  describe '.js_number_to_s' do
    it 'formats numbers like JavaScript' do
      {
        1 => '1', 1.0 => '1', 1.5 => '1.5', 1e21 => '1e+21', 1e-7 => '1e-7', 0.000002 => '0.000002',
        1.23e-18 => '1.23e-18', 1e23 => '1e+23', -0.0 => '0', -1.5 => '-1.5', 1e20 => '100000000000000000000',
        123.456 => '123.456', 0.1 => '0.1', Float::NAN => 'NaN', -Float::INFINITY => '-Infinity'
      }.each { |input, expected| expect(described_class.js_number_to_s(input)).to eq(expected), input.inspect }
    end
  end
end
