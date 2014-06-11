require 'rake'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)
task :default => :spec

desc 'Open a Pry console with environment'
task :console do
  exec "pry -Ilib -rfilter_io"
end
