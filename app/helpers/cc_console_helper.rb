module CcConsoleHelper
  def get_console_url_per_environment
    default_url =
      if Rails.env.development? || Rails.env.test?
        "http://localhost:3001"
      else
        "https://console.footlight.io"
      end

    ENV.fetch("CONSOLE_URL", default_url).chomp("/")
  end
end