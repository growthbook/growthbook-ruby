# frozen_string_literal: true

# Running `rake` runs all specified tasks in the list
task default: %i[test type_check lint_fix doc]

task ci: %i[test type_check lint]

task :test do
  sh 'bundle', 'exec', 'rspec'
end

task :type_check do
  sh 'steep', 'check', '--log-level=fatal'
end

task :lint do
  sh 'rubocop'
end

task :lint_fix do
  sh 'rubocop', '-A'
end

task :doc do
  sh 'yard', 'doc', 'lib/**/*.rb'
end
