# Contributing Guide

We welcome all contributions!

## Requirements

-   Ruby version 3.1.1+

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

Install the required gem:

    gem install steep -v 1.6.0

You may find the following tools helpful:

-   [Steep VSCode plugin](https://github.com/soutaro/steep-vscode) provides inline type validation
-   RubyMine IDE makes it easier to edit type definitions

## Releasing

Releases are made by [release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/) on `main`:

1. Merge PRs with conventional titles (`feat:`, `fix:`, `feat!:` …). Release-please keeps a
   "chore: release X.Y.Z" PR open that bumps `lib/growthbook/version.rb`, `Gemfile.lock` and
   `CHANGELOG.md`.
2. Merge the release PR. Release-please tags `vX.Y.Z`, creates the GitHub release, and the
   workflow runs the tests and publishes the gem to RubyGems.
