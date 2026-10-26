# frozen_string_literal: true

require 'spec_helper'
require 'growthbook'

RSpec.describe 'payload reduction' do
  describe '.prune_condition' do
    it 'accepts symbol keys' do
      expect(Growthbook.prune_condition({ id: '123' }, { id: '123', country: 'US' })).to eq({ 'country' => 'US' })
    end
  end

  describe '.reduce_payload' do
    let(:payload) do
      {
        'features' => {
          'android' => { 'defaultValue' => 1, 'metadata' => { 'customFields' => { 'platform' => ['android'] } } },
          'ios'     => { 'defaultValue' => 2, 'metadata' => { 'customFields' => { 'platform' => ['ios'] } } },
          'beta'    => { 'defaultValue' => false, 'rules' => [{ 'condition' => { 'id' => '123' }, 'force' => true }] }
        }
      }
    end

    it 'accepts symbol keys and custom_fields for customFields' do
      result = Growthbook.reduce_payload(payload, include: { custom_fields: { platform: ['android'] } })
      expect(result['features'].keys).to eq(['android'])
    end

    it 'does not modify the payload' do
      original = Marshal.load(Marshal.dump(payload))
      result = Growthbook.reduce_payload(payload, attributes: { id: '123' })
      expect(result['features']['beta']['rules']).to eq([{ 'force' => true }])
      expect(payload).to eq(original)
    end
  end
end
