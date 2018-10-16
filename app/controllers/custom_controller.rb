class CustomController < ApplicationController
  def get_comotion_locations
    params[:ids] ||= '42645,42694'
    id_list = params[:ids].split(',')
    base_url = "https://www.reservatech.net/SelectTickets.aspx?EventDateId="

    agent = Mechanize.new
    agent.user_agent_alias = 'Mac Safari'

    @locations = []
    id_list.each do |id|
      # get html page from
      url = base_url + id
      #scrape url
      page = agent.get(url)

      location = page.xpath("//span[@id='PageContentHolder_ctl00_lblVenueName']")
      #extract location
      @locations << location.text
    end

    render json: @locations

  end
end
