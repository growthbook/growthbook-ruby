# frozen_string_literal: true

require 'growthbook'
require 'json'

file = File.read(File.join(File.dirname(__FILE__), 'cases.json'))
test_cases = JSON.parse(file)

def roundArray(arr)
  return arr.map { 
    |v| (v.is_a?(Float) || v.is_a?(Integer)) ? v.round(5) : roundArray(v) 
  }
end

describe 'test suite' do
  # Test the 'getBucketRange' function
  describe 'getBucketRanges' do
    # Loop through each test case in the JSON file
    test_cases['getBucketRange'].each do |test_case|
      # Extract data about the test case
      test_name, args, expected = test_case
      num_variations, coverage, weights = args

      # Run the actual test case
      it test_name.to_s do
        result = Growthbook::Util.getBucketRanges(
          num_variations,
          coverage,
          weights
        )

        expect(roundArray(result)).to eq(roundArray(expected))
      end
    end
  end
end
