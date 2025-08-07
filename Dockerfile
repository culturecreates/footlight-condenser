# Base Image - Use Ruby official image
FROM ruby:2.7.8

# This sets the base image to Ruby 2.7.8. You can check your Ruby version with:
# ruby --version
# Use the version that matches your project requirements

# Update package lists and install system dependencies
RUN apt-get update -qq && apt-get install -y \
    nodejs \
    postgresql-client \
    build-essential \
    libpq-dev \
    yarn

# Explanation of each package:
# - nodejs: Required for Rails asset pipeline and JavaScript runtime
# - postgresql-client: Tools to connect to PostgreSQL database
# - build-essential: Compiler tools needed for native gem extensions
# - libpq-dev: PostgreSQL development headers for pg gem
# - yarn: Package manager for JavaScript dependencies (if using Webpacker)

# Set the working directory inside the container
WORKDIR /app

# This creates and sets /app as the working directory
# All subsequent commands will run from this directory

# Copy Gemfile and Gemfile.lock first (for better caching)
COPY Gemfile  ./

RUN gem install bundler:2.4.22

# Docker caches layers, so copying Gemfile separately means
# gem installation only runs when Gemfile changes, not when code changes

# Install Ruby gems
RUN bundle lock --add-platform x86_64-linux
RUN bundle install

# bundle config --global frozen 1 ensures gems are installed exactly 
# as specified in Gemfile.lock for reproducible builds

# Copy the rest of the application code
COPY . .

# This copies all files from your project directory to /app in the container
# Files listed in .dockerignore will be excluded

# Create directories that Rails expects
RUN mkdir -p tmp/pids

# Rails needs tmp/pids directory for process ID files

# Precompile assets (optional, for production)
# RUN RAILS_ENV=production bundle exec rails assets:precompile

# Expose port 3000 to allow external connections
EXPOSE 3000

# This doesn't actually publish the port, it's documentation
# The actual port mapping happens when running the container

# Set the default command to start the Rails server
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

# -b 0.0.0.0 binds the server to all interfaces, not just localhost
# This allows external connections to reach the Rails app