# Contributing Guide

We welcome all contributions!

## Testing

Run unit tests with `bundler exec rspec`

## Linting

To use the linter, install it:

    gem install rubocop -v 1.50.2
    gem install rubocop-rspec -v 2.20.0


## Releasing

1. Bump version in `Gemfile.lock` and `growthbook.gemspec`
2. Merge to the `main` branch
3. Create a new GitHub release with the new version as the tag (e.g. `v0.2.0`)
4. Run `gem build growthbook`
5. Run `gem push growthbook-{VERSION}.gem`
