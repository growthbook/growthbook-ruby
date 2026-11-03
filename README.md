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

## Caching fetched features

`FeatureRepository#fetch` caches the payload for 60 seconds by default, in a cache shared by every repository in the process. Repositories are usually built per request, so a per-instance cache would be empty on every fetch and the TTL would never take effect.

```ruby
repo = Growthbook::FeatureRepository.new(
  endpoint: 'https://cdn.growthbook.io/api/features/sdk-abc123',
  decryption_key: nil,
  ttl: 60        # seconds; nil never expires
)

repo.fetch               # hits the API
repo.fetch               # served from cache
repo.fetch(force: true)  # skips the cache and overwrites the entry
```

`ttl` governs what a repository *writes*, not what it reads, so an entry another repository put in the shared cache is served regardless of yours. `fetch(force: true)` is the supported way past it.

Pass `cache: false` to disable caching entirely, or `cache: <your own>` to bring your own store — subclass `Growthbook::FeatureCache` and implement `get` / `set` / `clear`.

