# frozen_string_literal: true

# Wesbites needing custom code
class CustomController < ApplicationController
  def get_comotion_locations
    params[:ids] ||= '42645,42694'
    params[:sleep_sec] ||= '1'
    id_list = params[:ids].split(',')
    base_url = 'https://www.reservatech.net/SelectTickets.aspx?EventDateId='

    agent = Mechanize.new
    agent.user_agent_alias = 'Mac Safari'

    @locations = []
    id_list.each do |id|
      # get html page from
      url = base_url + id
      # scrape url
      logger.info "*** Getting html from wringer url:#{url}"
      html = agent.get_file  helpers.use_wringer(url)
      page = Nokogiri::HTML html
      logger.info "*** Testing for blank title = #{page.xpath('//title').text}"
      if page.xpath('//title').text.blank?
        # title is blank when you need to wait in queue for ticketing system
        sleep params[:sleep_sec].to_i

        url_force_scrape = helpers.use_wringer(url) + '&force_scrape=true'
        logger.info "*** RESCRAPING: #{url_force_scrape} "
        html = agent.get_file url_force_scrape
        page = Nokogiri::HTML html
      end
      location = page.xpath("//span[@id='PageContentHolder_ctl00_lblVenueName']")
      date = page.xpath("//span[@id='PageContentHolder_ctl00_lblEventDate']")
      # extract
      @locations << date.text + ' @ ' + location.text
      if id_list.count >= 2
        logger.info "*** Waiting:#{params[:sleep_sec].to_i} seconds"
        sleep params[:sleep_sec].to_i
      end
    end

    # if all locations are the same then collapse into a single location
    @locations.uniq! if @locations.uniq.count == 1

    render json: @locations
  end
end
