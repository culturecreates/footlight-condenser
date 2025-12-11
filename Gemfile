source 'https://rubygems.org'

ruby '3.4.4'

# Core
gem 'rails', '~> 8.0.2'
gem 'pg', '~> 1.5'
gem 'puma', '~> 6.4'
gem 'sassc-rails' # replaces deprecated sass-rails
gem 'jbuilder', '~> 2.11'

# Modern asset bundling
gem 'jsbundling-rails'  # Replaces Uglifier (uses esbuild, rollup, or webpack)
# gem 'cssbundling-rails' # Optional, if you want to use Tailwind/PostCSS/etc.

# HTTP / Parsing / RDF
gem 'httparty'
gem 'mechanize'
gem 'linkeddata', '~> 3.2.0'
gem 'sparql', '3.2.0'
gem 'will_paginate', '~> 3.3'
gem 'chronic_duration'

# Background jobs & AWS
gem 'sidekiq'
gem 'aws-sdk-s3'

# Monitoring
gem 'scout_apm'

# CORS
gem 'rack-cors'

group :development, :test do
  gem 'byebug'
  gem 'capybara', '~> 3.40'
  gem 'selenium-webdriver', '>= 4.0'
  gem 'mocha'
  gem 'webmock'
  gem 'vcr'
  gem 'minitest'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-performance', require: false
end

group :development do
  gem 'web-console', '>= 4.0'
  gem 'listen', '~> 3.7'
  gem 'solargraph'
  gem 'derailed_benchmarks'
end

group :test do
  gem 'rails-controller-testing'
  gem 'simplecov', require: false
end

# Windows/Platform-specific
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

gem "turbo-rails", "~> 2.0"

gem "rubocop-minitest", "~> 0.38.1"

gem "rubocop-capybara", "~> 2.22"
