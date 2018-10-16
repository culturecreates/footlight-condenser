

class CustomController < ApplicationController
  def get_comotion_locations
    params[:ids] ||= '42645,42694'
    params[:sleep_sec] ||= '2'
    id_list = params[:ids].split(',')
    base_url = "https://www.reservatech.net/SelectTickets.aspx?EventDateId="

    agent = Mechanize.new
    agent.user_agent_alias = 'Mac Safari'

    @locations = []
    id_list.each do |id|
      # get html page from
      url = base_url + id
      #scrape url
      logger.info ("Getting html from wringer url:#{url}")
      html = agent.get_file  helpers.use_wringer(url)
      page = Nokogiri::HTML html
      location = page.xpath("//span[@id='PageContentHolder_ctl00_lblVenueName']")
      #extract location
      @locations << location.text
      logger.info ("Waiting:#{params[:sleep_sec].to_i} seconds")
      sleep params[:sleep_sec].to_i if id_list.count >= 2
    end

    # if all locations are the same then collapse into a single location
    @locations.uniq! if @locations.uniq.count == 1

    render json: @locations

  end
end
