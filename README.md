![](https://docs.growthbook.io/images/hero-ruby-sdk.png)

# GrowthBook Ruby SDK

[GrowthBook](https://www.growthbook.io) is a modular feature flagging and experimentation platform.

This is the Ruby client library that lets you evaluate feature flags and run experiments (A/B tests) within a Ruby application.

![Build Status](https://github.com/growthbook/growthbook-ruby/workflows/Build/badge.svg) [![Gem Version](https://badge.fury.io/rb/growthbook.svg)](https://badge.fury.io/rb/growthbook) ![Code coverage badge](badge.svg)

## Installation

Install the gem:

    gem install growthbook


## Usage Guide

See the [official documentation](https://docs.growthbook.io/lib/ruby).

## Contextual Bandits

A contextual bandit reallocates experiment traffic per segment: each segment ("leaf") carries a targeting condition and its own variation weights. All the optimisation happens on the GrowthBook backend — the SDK only picks the leaf that matches the user and buckets with the weights it supplies.

Definitions arrive with the feature payload under `contextualBandits`, keyed by the `contextualBanditRef` a feature rule points at, and are passed straight into the context:

```ruby
repository = Growthbook::FeatureRepository.new(
  endpoint: 'https://cdn.growthbook.io/api/features/sdk-abc123',
  decryption_key: nil
)
features = repository.fetch

gb = Growthbook::Context.new(
  features: features,
  contextual_bandits: repository.contextual_bandits_json,
  attributes: { id: 'user-123', plan: 'pro' }
)

gb.feature_value('checkout_button')
```

An encrypted payload (`encryptedContextualBandits`) is decrypted with the repository's `decryption_key`, like the features themselves.

When a bandit routed the assignment, the experiment result reports which leaf did it and with what weights:

```ruby
result = gb.eval_feature('checkout_button').experiment_result

result.leaf_id           # => 1, or -1 when no leaf matched
result.variation_weights # => [0.9, 0.1]
result.bandit_version    # => 7, the generation of the backend-computed weights
```

These are reported only for a real exposure. A forced variation, QA mode or a user filtered out of the experiment reports nothing, even though the weights were applied.

If the `contextualBanditRef` cannot be resolved in the payload, the rule keeps its own aggregate weights and no bandit metadata is reported, so an SDK that is behind the payload degrades to a plain experiment rather than failing.

