# Contributing Guide

We welcome all contributions!

## Testing

Run unit tests with `bundler exec rspec`

## Releasing

1. Bump version in `Gemfile.lock` and `growthbook.gemspec`
2. Merge to the `main` branch
3. Create a new GitHub release with the new version as the tag (e.g. `v0.2.0`)
4. Run `gem build growthbook`
5. Run `gem push growthbook-{VERSION}.gem`