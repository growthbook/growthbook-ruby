# Contributing Guide

We welcome all contributions!


## Requirements

- Ruby version 3.1.1+


## Rake tasks

There are numerous tasks available to help with development in the Rakefile.

You can also run any of those tasks manually. See each section below.


## Testing

Run unit tests with `bundler exec rspec`

## Linting

To use the linter, install it:

    gem install rubocop -v 1.50.2
    gem install rubocop-rspec -v 2.20.0
    gem install rubocop-performance -v 1.15

To auto-fix formatting, run the following:

    rubocop -x

To auto-fix correctable linting errors, run the following:

    rubocop -A

To run it as CI would, run:

    rubocop

If you use Visual Studio Code, you can use the extension [ruby-rubocop](https://marketplace.visualstudio.com/items?itemName=misogi.ruby-rubocop) to see editor hints.


## Type checking

The project uses RBS for type definitions and Steep for type checking.

RBS comes preinstalled with Ruby version 3+.

You may find the following tools helpful:

- [Steep VSCode plugin](https://github.com/soutaro/steep-vscode) provides inline type validation
- RubyMine IDE makes it easier to edit type definitions


## Releasing

1. Bump version in `Gemfile.lock` and `growthbook.gemspec`
2. Merge to the `main` branch
3. Create a new GitHub release with the new version as the tag (e.g. `v0.2.0`)
4. Run `gem build growthbook`
5. Run `gem push growthbook-{VERSION}.gem`
