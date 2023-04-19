# frozen_string_literal: true

require 'growthbook'

describe 'util' do
  describe 'checkRule function' do
    it 'works for all operators and normal inputs' do
      # =
      expect(Growthbook::Util.check_rule('test', '=', 'test')).to be(true)
      expect(Growthbook::Util.check_rule('test', '=', 'other')).to be(false)
      # !=
      expect(Growthbook::Util.check_rule('test', '!=', 'other')).to be(true)
      expect(Growthbook::Util.check_rule('test', '!=', 'test')).to be(false)
      # >
      expect(Growthbook::Util.check_rule('b', '>', 'a')).to be(true)
      expect(Growthbook::Util.check_rule('a', '>', 'b')).to be(false)
      # <
      expect(Growthbook::Util.check_rule('a', '<', 'b')).to be(true)
      expect(Growthbook::Util.check_rule('b', '<', 'a')).to be(false)
      # ~
      expect(Growthbook::Util.check_rule('123-456-abc', '~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(true)
      expect(Growthbook::Util.check_rule('123-abc-456', '~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(false)
      # !~
      expect(Growthbook::Util.check_rule('123-abc-456', '!~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(true)
      expect(Growthbook::Util.check_rule('123-456-abc', '!~', '^[0-9]{3}-[0-9]{3}-[a-z]{3}$')).to be(false)
    end

    it "returns true when there's an unknown operator" do
      expect(Growthbook::Util.check_rule('abc', '*', '123')).to be(true)
    end

    it 'returns false when the regex is invalid' do
      expect(Growthbook::Util.check_rule('abc', '~', 'abc)')).to be(false)
    end

    it 'compares numeric strings with natural ordering' do
      expect(Growthbook::Util.check_rule('10', '>', '9')).to be(true)
      expect(Growthbook::Util.check_rule('9', '<', '1000')).to be(true)
      expect(Growthbook::Util.check_rule('90', '>', '800')).to be(false)
      expect(Growthbook::Util.check_rule('-10', '<', '10')).to be(true)
      expect(Growthbook::Util.check_rule('10', '>', 'abc')).to be(false)
    end

    it 'checks for numeric equality properly' do
      expect(Growthbook::Util.check_rule('9.0', '=', '9')).to be(true)
      expect(Growthbook::Util.check_rule('1.3', '!=', '1.30000')).to be(false)
    end

    it 'handles empty strings' do
      expect(Growthbook::Util.check_rule('', '=', '')).to be(true)
      expect(Growthbook::Util.check_rule('', '!=', '')).to be(false)
      expect(Growthbook::Util.check_rule('', '>', '')).to be(false)
      expect(Growthbook::Util.check_rule('', '<', '')).to be(false)
      expect(Growthbook::Util.check_rule('', '~', '')).to be(true)
      expect(Growthbook::Util.check_rule('', '!~', '')).to be(false)
    end
  end

  describe 'chooseVariation function' do
    it 'does not have a sample ratio mismatch bug' do
      # Full coverage
      experiment = Growthbook::Experiment.new('my-test', 2)
      variations = [0, 0]
      1000.times do |i|
        variations[Growthbook::Util.choose_variation_for_user(i.to_s, experiment)] += 1
      end
      expect(variations[0]).to eq(503)
    end

    it 'does not have a sample ratio mismatch bug for reduced coverage' do
      # Reduced coverage
      experiment = Growthbook::Experiment.new('my-test', 2, coverage: 0.4)
      var0 = 0
      var1 = 0
      varn = 0
      1000.times do |i|
        result = Growthbook::Util.choose_variation_for_user(i.to_s, experiment)
        case result
        when -1
          varn += 1
        when 0
          var0 += 1
        else
          var1 += 1
        end
      end
      expect(var0).to eq(200)
      expect(var1).to eq(204)
      expect(varn).to eq(596)
    end

    it 'assigns variations with default weights' do
      experiment = Growthbook::Experiment.new('my-test', 2)

      expect(Growthbook::Util.choose_variation_for_user('1', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('2', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('3', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('4', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('5', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('6', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('7', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('8', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('9', experiment)).to eq(0)
    end

    it 'assigns variations with uneven weights' do
      experiment = Growthbook::Experiment.new('my-test', 2, weights: [0.1, 0.9])

      expect(Growthbook::Util.choose_variation_for_user('1', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('2', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('3', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('4', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('5', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('6', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('7', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('8', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('9', experiment)).to eq(1)
    end

    it 'assigns variations with reduced coverage' do
      experiment = Growthbook::Experiment.new('my-test', 2, coverage: 0.4)

      expect(Growthbook::Util.choose_variation_for_user('1', experiment)).to eq(-1)
      expect(Growthbook::Util.choose_variation_for_user('2', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('3', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('4', experiment)).to eq(-1)
      expect(Growthbook::Util.choose_variation_for_user('5', experiment)).to eq(-1)
      expect(Growthbook::Util.choose_variation_for_user('6', experiment)).to eq(-1)
      expect(Growthbook::Util.choose_variation_for_user('7', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('8', experiment)).to eq(-1)
      expect(Growthbook::Util.choose_variation_for_user('9', experiment)).to eq(1)
    end

    it 'assigns variations with default 3 variations' do
      experiment = Growthbook::Experiment.new('my-test', 3)

      expect(Growthbook::Util.choose_variation_for_user('1', experiment)).to eq(2)
      expect(Growthbook::Util.choose_variation_for_user('2', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('3', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('4', experiment)).to eq(2)
      expect(Growthbook::Util.choose_variation_for_user('5', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('6', experiment)).to eq(2)
      expect(Growthbook::Util.choose_variation_for_user('7', experiment)).to eq(0)
      expect(Growthbook::Util.choose_variation_for_user('8', experiment)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('9', experiment)).to eq(0)
    end

    it 'uses experiment name to choose a variation' do
      experiment1 = Growthbook::Experiment.new('my-test', 2)
      experiment2 = Growthbook::Experiment.new('my-test-3', 2)

      expect(Growthbook::Util.choose_variation_for_user('1', experiment1)).to eq(1)
      expect(Growthbook::Util.choose_variation_for_user('1', experiment2)).to eq(0)
    end
  end
end
