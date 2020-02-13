module CcConsoleHelper

    def get_console_url_per_environment
        if Rails.env.development?  || Rails.env.test?
            "http://localhost:3001"
        else
            "https://console.artsdata.ca"
        end
    end

end