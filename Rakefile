require 'rubygems'
require 'rake'
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

task :test => :check_dependencies

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "filter_io"
    gem.summary = "Filter IO streams with a block. Ruby's FilterInputStream."
    gem.email = "jason@jasoncodes.com"
    gem.homepage = "http://github.com/jasoncodes/filter_io"
    gem.authors = ["Jason Weathered"]
    gem.has_rdoc = false
    gem.add_dependency 'activesupport'
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
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
