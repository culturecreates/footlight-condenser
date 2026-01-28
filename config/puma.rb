# config/puma.rb

# Specifies the number of workers (for clustered mode)
workers 0

# Min and max threads per worker
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

# Preload app for performance (optional, helps with Copy-On-Write)
preload_app!

# Port to listen on
port ENV.fetch("PORT") { 4000 }

# Set environment
environment ENV.fetch("RAILS_ENV") { "development" }

# On worker boot — re-establish DB connection
if ENV['RAILS_ENV'] == 'production'
  on_worker_boot do
    ActiveRecord::Base.establish_connection
  end
end


# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
