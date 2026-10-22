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

## Remote Evaluation

With remote evaluation, feature flags are evaluated on a self-hosted GrowthBook proxy or edge worker instead of locally in the SDK. Instead of downloading the full feature definitions, the SDK sends the current evaluation context (attributes, forced variations, forced features and URL) to the proxy via a `POST` request and gets back only the already-evaluated features, so targeting logic and unexposed feature values stay off the client.

```ruby
repository = Growthbook::RemoteEvalRepository.new(
  api_host: 'https://gb-proxy.example.com',
  client_key: 'sdk-abc123'
)

# Sends a POST to https://gb-proxy.example.com/api/eval/sdk-abc123
gb = Growthbook::Context.new(
  remote_eval_repository: repository,
  attributes: { id: 'user-123' }
)

gb.on?('dark_mode')
```

### Requirements and constraints

Remote evaluation requires a **self-hosted** proxy or edge worker and is **not** supported on GrowthBook Cloud. The following raise an `ArgumentError`:

- a GrowthBook Cloud host (`*.growthbook.io`) — point `api_host` at your own proxy/edge;
- a `decryption_key` — encryption is handled by the proxy, not the SDK;
- a `sticky_bucket_service` — sticky bucketing is handled server-side;
- an `api_host` that is not an absolute URL, or uses a scheme other than `http`/`https`.

`api_host` must use `https`: the request body carries user attributes and the URL carries the client key, so neither may travel in the clear. A plaintext `http` host is allowed on loopback (`localhost`, `127.0.0.0/8`, `::1`), and elsewhere only with an explicit opt-in — use it when the proxy is reachable only over a trusted network, for example in-cluster behind a TLS-terminating load balancer:

```ruby
Growthbook::RemoteEvalRepository.new(
  api_host: 'http://growthbook-proxy.internal:3300',
  client_key: 'sdk-abc123',
  allow_insecure_http: true
)
```

### Re-evaluation when the context changes

Because the proxy evaluates features for one specific context, the SDK re-evaluates whenever that context changes: `attributes=`, `forced_variations=`, `forced_features=` and `url=` all trigger a new request. Responses are cached per context, so repeated contexts are served without a network call.

```ruby
gb.attributes = { id: 'user-123', country: 'FR' } # re-evaluates for the new attributes
```

Feature changes made on the server while the context stays the same are picked up by `refresh_for_remote_eval`, which refetches once the cached response is older than the TTL:

```ruby
gb.refresh_for_remote_eval
```

If the proxy is unreachable, a stale cached response is used when there is one — it is keyed by the evaluation context, so it belongs to the right user. Otherwise `refresh_for_remote_eval` returns `false`, and what happens to the current features depends on whether the context moved: they are kept when it did not, and discarded when it did, so evaluation falls back to defaults rather than reporting the previous user's values under the new identity. Features the application supplied itself are never discarded.

### Caching

By default every attribute is part of the cache key. Use `cache_key_attributes` to narrow it, so that changes to irrelevant attributes do not cause extra requests. Forced features are deliberately excluded from the key: they are applied on this side and the proxy does not filter on them.

```ruby
Growthbook::RemoteEvalRepository.new(
  api_host: 'https://gb-proxy.example.com',
  client_key: 'sdk-abc123',
  cache_key_attributes: ['id'], # only `id` affects the cache key
  cache_ttl: 60                 # seconds a response is reused
)
```

Caching defaults to a per-process `Growthbook::InMemoryRemoteEvalCache` (TTL plus an LRU bound of 1000 entries). Pass `cache: nil` to disable it, or subclass `Growthbook::RemoteEvalCache` to back it with a store shared between processes:

```ruby
class RedisRemoteEvalCache < Growthbook::RemoteEvalCache
  def get(key)
    raw = REDIS.get(key)
    raw && JSON.parse(raw)
  end

  def set(key, value, ttl)
    REDIS.set(key, JSON.generate(value), ex: ttl)
  end
end
```

