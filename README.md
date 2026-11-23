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

## Streaming feature updates

When the GrowthBook API supports Server-Sent Events, `FeatureRepository` can keep features up to date from a background thread instead of fetching them again.

```ruby
# Once, at boot (e.g. config/initializers/growthbook.rb)
GROWTHBOOK = Growthbook::FeatureRepository.new(
  endpoint: 'https://cdn.growthbook.io/api/features/sdk-abc123',
  decryption_key: nil
)
GROWTHBOOK.fetch
GROWTHBOOK.start_auto_refresh(
  on_update: ->(features, _saved_groups) { puts "GrowthBook: #{features.size} features" }
)

# Per request
features, saved_groups = GROWTHBOOK.snapshot
context = Growthbook::Context.new(features: features, saved_groups: saved_groups, attributes: { id: '123' })
```

- Call `fetch` first. Streaming starts only if that response carried `x-sse-support: enabled`; otherwise `start_auto_refresh` prints a warning and returns `false`.
- Read with `snapshot` while streaming: it returns features and saved groups from the same update, whereas `features_json` and `saved_groups_json` read separately may straddle one.
- A dropped connection or a 5xx is retried with a growing delay (1–2 seconds at first, doubling up to 60). A 4xx other than 408 and 429 means the key or URL is wrong, so the stream stops.
- Forking servers (Puma in cluster mode, Unicorn) need no extra setup: a worker starts its own stream the first time it reads features. The stream is closed when the process exits, or earlier with `stop_auto_refresh`.
- Pass `streaming_host:` when the stream is served from a different host than the API, and `headers:` to add request headers.

