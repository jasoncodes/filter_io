require 'rake'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)
task :default => :spec

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |t|
    t.libs << "test"
    t.rcov_opts = [
      "--exclude '^(?!lib)'"
    ]
    t.test_files = FileList[
      'test/**/*_test.rb'
    ]
    t.output_dir = 'coverage'
    t.verbose = true
  end
  task :rcov do
    system "open coverage/index.html"
  end
rescue LoadError
  task :rcov do
    raise "You must install the 'rcov' gem"
  end
end
