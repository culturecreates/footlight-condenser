module CcConsoleHelper
  def get_console_url_per_environment
    cookies.signed[:console_inspection_url].presence || configured_console_url
  end

  def configured_console_url
    default_url =
      if Rails.env.development? || Rails.env.test?
        "http://localhost:3001"
      else
        "https://console.footlight.io"
      end

    ENV.fetch("CONSOLE_URL", default_url).chomp("/")
  end
end
