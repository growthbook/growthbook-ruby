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


## Tracking events

The SDK sends a `Feature Evaluated` event when a feature is evaluated and an `Experiment Viewed`
event when a user is put in an experiment. Each one is sent once per context until its value
changes. Pass an `event_logger` to receive them, and send your own events with `log_event`:

```ruby
gb = Growthbook::Context.new(
  attributes: { id: 'user-123' },
  features: features,
  event_logger: ->(event_name, properties, user_context) { MyAnalytics.track(event_name, properties, user_context) }
)

gb.on?('new-checkout')                     # sends "Feature Evaluated"
gb.log_event('Checkout Started', { 'step' => 1 })
```

`user_context` is `{ attributes:, url: }`. A `Context` is not thread-safe: create one per
request or thread.

### Plugins

`plugins:` takes objects that respond to `call(context)`. Each one is called once, at the end of
`Context.new`. An error raised by a plugin is not rescued.

### GrowthBook tracking plugin

`Growthbook::Plugins::Tracking` sends these events to GrowthBook. Create it once per process and
pass it to every context, together with your SDK client key:

```ruby
# config/initializers/growthbook.rb
GROWTHBOOK_TRACKING = Growthbook::Plugins::Tracking.new

# per request
gb = Growthbook::Context.new(
  client_key: ENV.fetch('GROWTHBOOK_CLIENT_KEY'),
  attributes: { id: current_user_id },
  features: features,
  plugins: [GROWTHBOOK_TRACKING]
)
```

Events are queued and sent in batches from a background thread, deduplicated across contexts, and
flushed when a context is destroyed and at exit. The plugin is thread-safe and fork-safe.

| Option | Default | |
| --- | --- | --- |
| `ingestor_host` | `https://us-east-1.gb-ingest.com` | Where events are sent |
| `queue_flush_interval` | `0.1` | Seconds to collect events into one request |
| `enable` | `true` | `false` filters and dedupes events but doesn't send them |
| `enable_feature_usage_events` | `true` | `false` stops sending `Feature Evaluated` |
| `event_filter` | `nil` | Called with `{ event_name:, properties:, attributes:, url: }`; return a falsy value to drop the event |
| `dedupe_cache_size` | `1000` | How many recent events are remembered for deduplication |
| `dedupe_key_attributes` | `[]` | Attributes that identify a user for deduplication (default: all of them) |
| `max_queue_size` | `10000` | Events queued beyond this are dropped |
| `http_timeout` | `5` | Open and read timeout, in seconds |
| `debug` | `false` | Write each event to stderr |

Call `flush` to send the queue right away, e.g. at the end of a background job.

**Personal data.** Every attribute of the user is sent to the ingestor: `user_id`, `device_id`
(or `anonymous_id`, `id`), `page_id` and `session_id` as top-level fields, the rest in
`context_json`. Only pass the attributes you are allowed to share, or drop events with
`event_filter`. `debug` writes the attributes to your logs.
