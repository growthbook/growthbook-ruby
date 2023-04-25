# frozen_string_literal: true

task :test do
  sh 'bundle', 'exec', 'rspec'
end

task :type_check do
  sh 'steep', 'check', '--log-level=fatal'
end

# Requires that Rubocop is installed. See CONTRIBUTING.md for details.
task :lint do
  sh 'rubocop'
end

# Requires that Rubocop is installed. See CONTRIBUTING.md for details.
task :lint_fix do
  sh 'rubocop', '-A'
end

task :doc do
  sh 'yard', 'doc', 'lib/**/*.rb'
end
