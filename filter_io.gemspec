# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'filter_io/version'

Gem::Specification.new do |spec|
  spec.name = %q{filter_io}
  spec.version = FilterIO::VERSION
  spec.authors = ['Jason Weathered']
  spec.email = ['jason@jasoncodes.com']
  spec.summary = %q{Filter IO streams with a block. Ruby's FilterInputStream.}
  spec.homepage = 'http://github.com/jasoncodes/filter_io'
  spec.license = 'MIT'

  spec.files = `git ls-files`.split($/)
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 2.3.9'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 2.13'
end
