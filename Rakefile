require 'rake'
require 'bundler/gem_tasks'
require 'rake/testtask'

desc 'Default: run unit tests.'
task :default => :test

desc 'Test the filter_io plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

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
