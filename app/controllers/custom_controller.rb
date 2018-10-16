class CustomController < ApplicationController
  def get_comotion_locations
      @ids = params[:ids]

       id_list = params[:ids]
       base_url = "https://www.reservatech.net/SelectTickets.aspx?EventDateId="

      #
      # id_list.each do |id|
      #   # get html page from
      #   url = base_url + id
      #   #scrape url
      #   page = agent.get(url)
      #
      #   location = page.xpath("//row")
      #   #extract location
      #   locations << location
      # end

      render json: {"hi":"there"}

  end
end
