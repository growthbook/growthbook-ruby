# frozen_string_literal: true

require 'growthbook'
require 'json'

file = File.read(File.join(File.dirname(__FILE__), 'cases.json'))
test_cases = JSON.parse(file)

def roundArray(arr)
  arr.map do |v|
    v.is_a?(Float) || v.is_a?(Integer) ? v.round(5) : roundArray(v)
  end
end

describe 'test suite' do
  describe 'hash' do
    test_cases['hash'].each do |test_case|
      value, expected = test_case

      it value do
        result = Growthbook::Util.hash(value)
        expect(result.round(5)).to eq expected.round(5)
      end
    end
  end

  describe 'getBucketRanges' do
    # Loop through each test case in the JSON file
    test_cases['getBucketRange'].each do |test_case|
      # Extract data about the test case
      test_name, args, expected = test_case
      num_variations, coverage, weights = args

      # Run the actual test case
      it test_name do
        result = Growthbook::Util.get_bucket_ranges(
          num_variations,
          coverage,
          weights
        )

        expect(roundArray(result)).to eq(roundArray(expected))
      end
    end
  end

  describe 'chooseVariation' do
    # Loop through each test case in the JSON file
    test_cases['chooseVariation'].each do |test_case|
      # Extract data about the test case
      test_name, n, ranges, expected = test_case

      # Run the actual test case
      it test_name do
        result = Growthbook::Util.choose_variation(n, ranges)
        expect(result).to eq(expected)
      end
    end
  end

  describe 'getQueryStringOverride' do
    # Loop through each test case in the JSON file
    test_cases['getQueryStringOverride'].each do |test_case|
      # Extract data about the test case
      test_name, key, url, num_variations, expected = test_case

      # Run the actual test case
      it test_name do
        result = Growthbook::Util.get_query_string_override(
          key,
          url,
          num_variations
        )
        expect(result).to eq(expected)
      end
    end
  end

  describe 'inNamespace' do
    # Loop through each test case in the JSON file
    test_cases['inNamespace'].each do |test_case|
      # Extract data about the test case
      test_name, id, namespace, expected = test_case

      # Run the actual test case
      it test_name do
        result = Growthbook::Util.in_namespace(
          id,
          namespace
        )
        expect(result).to eq(expected)
      end
    end
  end

  describe 'getEqualWeights' do
    # Loop through each test case in the JSON file
    test_cases['getEqualWeights'].each do |test_case|
      # Extract data about the test case
      num_variations, expected = test_case

      # Run the actual test case
      it num_variations.to_s do
        result = Growthbook::Util.get_equal_weights(
          num_variations
        )
        expect(roundArray(result)).to eq(roundArray(expected))
      end
    end
  end

  describe 'evalCondition' do
    # Loop through each test case in the JSON file
    test_cases['evalCondition'].each do |test_case|
      # Extract data about the test case
      test_name, condition, attributes, expected = test_case

      # Run the actual test case
      it test_name do
        result = Growthbook::Conditions.eval_condition(
          attributes,
          condition
        )
        expect(result).to eq(expected)
      end
    end
  end
  describe 'feature' do
    # Loop through each test case in the JSON file
    test_cases['feature'].each do |test_case|
      # Extract data about the test case
      test_name, context, key, expected = test_case

      # Run the actual test case
      it test_name do
        gb = Growthbook::Context.new(context)
        result = gb.eval_feature(key)
        expect(result.to_json).to eq(expected)
      end
    end
  end

  describe 'run' do
    # Loop through each test case in the JSON file
    test_cases['run'].each do |test_case|
      # Extract data about the test case
      test_name, context, experiment, value, in_experiment, hash_used = test_case

      # Run the actual test case
      it test_name do
        gb = Growthbook::Context.new(context)
        exp = Growthbook::InlineExperiment.new(experiment)
        result = gb.run(exp)
        expect(result.value).to eq(value)
        expect(result.in_experiment).to eq(in_experiment)
        expect(result.hash_used).to eq(hash_used)
      end
    end
  end
end
