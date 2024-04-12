# frozen_string_literal: true

module Growthbook
  # Extendable class that can be used as the tracking callback
  class StickyBucketService
    def get_assignments(_attribute_name, _attribute_value)
      nil
    end

    def save_assignments(_doc)
      nil
    end

    def get_key(attribute_name, attribute_value)
      "#{attribute_name}||#{attribute_value}"
    end

    def get_all_assignments(attributes)
      docs = {}
      attributes.each do |attribute_name, attribute_value|
        doc = get_assignments(attribute_name, attribute_value)
        docs[get_key(attribute_name, attribute_value)] = doc if doc
      end
      docs
    end
  end

  # Sample implementation (not meant for production use)
  class InMemoryStickyBucketService < StickyBucketService
    attr_accessor :assignments

    def initialize
      super
      @assignments = {}
    end

    def get_assignments(attribute_name, attribute_value)
      @assignments[get_key(attribute_name, attribute_value)]
    end

    def save_assignments(doc)
      @assignments[get_key(doc['attributeName'], doc['attributeValue'])] = doc
    end
  end
end
