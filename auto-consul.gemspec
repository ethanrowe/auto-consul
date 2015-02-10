require 'rake'
Gem::Specification.new do |s|
  s.name        = 'auto-consul'
  s.description = 'Ruby utilities to aid in the bootstrapping of EC2-based consul clusters'
  s.date        = '2014-05-12'
  s.author      = 'Ethan Rowe'
  s.email       = 'ethan@the-rowes.com'
  s.platform    = Gem::Platform::RUBY
  s.summary     = s.description
  s.license     = 'MIT'
  s.version     = '0.2.0'

  s.files       = FileList['lib/**/*.rb', 'spec/**/*.rb', 'bin/*', '[A-Z]*'].to_a
  s.executables << 'auto-consul'

  s.add_dependency('aws-sdk'   , '~> 2')
  s.add_dependency('aws-sdk-v1', '~> 1')
  s.add_development_dependency('bundler')
  s.add_development_dependency('rake')
  s.add_development_dependency('rspec')
end
