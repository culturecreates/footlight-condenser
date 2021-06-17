# frozen_string_literal: true

module StatementsHelper
  include CcKgHelper
  include CcWringerHelper
  Page = Struct.new(:text) # Used to simulate Nokogiri object's text method

  def scrape_sources(sources, webpage, scrape_options = {})
    logger.info("*** Starting scrape with sources:#{sources.inspect} for webpage: #{webpage.inspect}")
    sources.each do |source|
      #################################################
      # MAIN SCRAPE ACTIVITY
      _scraped_data = scrape(source, @next_step.nil? ? webpage.url : @next_step, scrape_options)
      #################################################

      if source.next_step.nil?
        @next_step = nil # clear to break chain of scraping urls

        #################################################
        # SECONDARY SCRAPE ACTIVITY - post process
        _data = format_datatype(_scraped_data, source.property, webpage)
        #################################################

        # add last startDate and endDate to ArchiveDate in Webpages Table to be able to sort by date and refresh event still to come.
        if (source.property.uri == 'http://schema.org/startDate' || source.property.uri == 'http://schema.org/endDate' ) && source.selected
          ## TODO: need to also check EventStatus is Postponed and set archive date to 1 year in the future.
          logger.info("*** Setting Last Show Date:#{_data}")
          # TODO: improve error handling to use consistent {error:}
          _data_string = _data&.to_s&.downcase
          if !_data_string.include?('error') && !_data_string.include?('bad')
            last_show_date = _data.class == Array ? _data.last : _data
            if last_show_date.present?
              webpage.archive_date = last_show_date.to_datetime - 24.hours
              if webpage.save
                logger.debug("*** set archive date for #{webpage.url} to #{webpage.archive_date}")
              else
                logger.error("*** ERROR: could not save archive date for #{webpage.url} using  #{last_show_date}.")
              end
            end
           end
        end

        s = Statement.where(webpage_id: webpage.id, source_id: source.id)
        # decide to create or update database entry
        if s.count != 1
          Statement.create!(cache: _data, webpage_id: webpage.id, source_id: source.id, status: 'initial', status_origin: 'condenser_refresh', cache_refreshed: Time.new)
        else
          # skip if source is manual and not missing
          unless source.algorithm_value.start_with?("manual=") && s.first.status != "missing"
            # preserve manually added and deleted links of datatype xsd:anyURI
            if source.property.value_datatype == 'xsd:anyURI'
                _data = preserve_manual_links _data, s.first.cache
            end
            # update database. Model automatically sets cache changed
            logger.info("*** Last step cache: #{_data}")
            first_statement =  s.first
            if _data&.to_s&.include?('abort_update')
              # set errors
              logger.error "###ERROR IN SCRAPE: Received 'abort_update' during scraping. #{_data}"
            else
              first_statement.cache = _data
              first_statement.cache_refreshed = Time.new
              first_statement.save
            end
          end
        end
      else
        # there is another step
        logger.info("*** First step cache: #{_scraped_data}")
        @next_step = _scraped_data.count == 1 ? _scraped_data : _scraped_data.first
      end
    end
  end

  def scrape(source, url, scrape_options = {})
    algorithm = source.algorithm_value
    if algorithm.start_with?('manual=')
      results_list = [algorithm.delete_prefix('manual=')]
    else
      begin
        agent = Mechanize.new
        agent.user_agent_alias = 'Mac Safari'
        html = agent.get_file  use_wringer(url, source.render_js, scrape_options) unless  algorithm.start_with?('url','ruby','post_url')
        # If response type is json then load json, otherwise load html in next line
        page = Nokogiri::HTML html
        results_list = []
        json_scraped = nil
        algorithm.split(';').each do |a|
          if a.start_with? 'url'
            # replace current page by scraping new url with wringer
            # using format url='http://example.com'
            new_url = a.delete_prefix('url=')
            new_url = new_url.gsub('$array', 'results_list')
            new_url = new_url.gsub('$url', 'url')
            new_url = eval(new_url)
            logger.info "*** New URL formed: #{new_url}"
            html = agent.get_file use_wringer(new_url, source.render_js, scrape_options)
            page = Nokogiri::HTML html
          elsif a.start_with? 'json_url'
            new_url = a.delete_prefix('url_json=')
            new_url = new_url.gsub('$array', 'results_list')
            new_url = new_url.gsub('$url', 'url')
            new_url = eval(new_url)
            logger.info "*** New URL for JSON call: #{new_url}"
            html = agent.get_file use_wringer(new_url, source.render_js, scrape_options)
            page = Page.new html  # Do not use Nokogiri because it will remove html
            #page = Nokogiri::HTML html
          elsif a.start_with? 'post_url'
            # replace current page data by scraping new url with wringer using POST
            # using format url='http://example.com?param_for_post='
            new_url = a.delete_prefix('post_url=')
            new_url = new_url.gsub('$array', 'results_list')
            new_url = new_url.gsub('$url', 'url')
            new_url = eval(new_url)
            logger.info "*** New POST URL formed: #{new_url}"
            temp_scrape_options = scrape_options.merge(json_post: true)
            data = agent.get_file use_wringer(new_url, source.render_js, temp_scrape_options)
            page = Nokogiri::HTML data
          elsif a.start_with? 'api'
            # Call API without going through wringer
            new_url = a.delete_prefix('api=')
            new_url = new_url.gsub('$array', 'results_list')
            new_url = new_url.gsub('$url', 'url')
            new_url = eval(new_url)
            logger.info "*** New json api URL formed: #{new_url}"
            data = HTTParty.get new_url
            logger.info "*** api response body: #{data.body}"
            results_list = JSON.parse(data.body)
          elsif a.start_with? 'ruby'
            command = a.delete_prefix('ruby=')
            command.gsub!('$array', 'results_list')
            command.gsub!('$url', 'url')
            command.gsub!('$json', 'json_scraped')
            results_list = eval(command)
          elsif a.start_with? 'xpath_sanitize'
            page_data = page.xpath(a.delete_prefix('xpath_sanitize='))
            page_data.each { |d| results_list << sanitize(d.to_s, tags: %w[h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br], attributes: %w[href]) }
          elsif a.start_with? 'if_xpath'
            page_data = page.xpath(a.delete_prefix('if_xpath='))
            break if page_data.blank?
            page_data.each { |d| results_list << d.text }
          elsif a.start_with? 'xpath'
            algo = a.delete_prefix('xpath=').gsub('$url', url)
            page_data = page.xpath(algo)
            page_data.each { |d| results_list << d.text }
          elsif  a.start_with? 'css'
            page_data = page.css(a.delete_prefix('css='))
            page_data.each { |d| results_list << d.text }
          elsif  a.start_with? 'time_zone'
            results_list << "time_zone: #{a.delete_prefix('time_zone=')}"
            logger.info "*** Adding time_zone: #{results_list}"
          elsif a.start_with? 'json'
            json_scraped = JSON.parse(page.text)
            ## use this pattern in source algorithm --> json=$json['name']
            command = a.delete_prefix('json=')
            command.gsub!('$json', 'json_scraped')
            results_list << eval(command)
          end
        end
      rescue StandardError => e
        logger.error(" ****************** Error in scrape: #{e.inspect}")
        results_list = [['abort_update'], ["error: #{e.inspect}"]]
      end
    end
    results_list
  end

  def is_condenser_formated_array(scraped_data)
    # check if scraped_data is already formated for condenser as an array in the case of hard coding (like event category).
    # example: scraped_data = ["[\"Manually added\",\"Category\",[\"Performance\" , \"http://ontology.artsdata.ca/Performance\"]]"]
    scraped_data[0][0] == '['
  rescue StandardError => e
    false
  end


  def convert_datetime(scraped_data)
    logger.info("Formatting dateTime with: #{scraped_data}")
    data = []
    # check for time_zone
    time_zone = nil
    scraped_data.each do |t|
      next unless t.class == String
      if t.start_with?('time_zone:')
        time_zone = t.split(':')[1].strip
        scraped_data.delete(t)
      end
    end
    scraped_data.each do |t|
      data << if time_zone
                ISO_dateTime(t, time_zone)
              else
                ISO_dateTime(t)
              end
    end
    data
  end

  def format_datatype(scraped_data, property, webpage)
    data = []
    if property.value_datatype == 'xsd:dateTime'
      data = convert_datetime(scraped_data)
    elsif property.value_datatype == 'xsd:date'
      data = convert_datetime(scraped_data).map {|d| d.to_date}
    elsif property.value_datatype == 'xsd:anyURI'
      unless scraped_data.blank?
        # first check if scraped_data is already formated as an array, and then parse and skip search.
        if is_condenser_formated_array(scraped_data)
          # parse URI set mannually
          data = JSON.parse(scraped_data[0])
        else
          # check for eventStatus
          if property.uri == 'http://schema.org/eventStatus'
            str = scraped_data.join(' - ')
            if str.scan(/\b(Cancelled|Annulé|Annule)/i).present?
              name = 'EventCancelled'
              uri = 'http://schema.org/EventCancelled'
            elsif str.scan(/\b(Postponed|Suspendu)/i).present?
              name = 'EventPostponed'
              uri = 'http://schema.org/EventPostponed'
            elsif str.scan(/\b(Rescheduled|reporté|reporte)/i).present?
              name = 'EventRescheduled'
              uri = 'http://schema.org/EventRescheduled'
            else
              name = 'EventScheduled'
              uri = 'http://schema.org/EventScheduled'
            end
            # data structure of uri = ['str', 'rdfs_class', ['name', 'uri']]
            data << [str, 'EventStatusType', [name, uri]]
          elsif property.uri == 'http://schema.org/additionalType'
            str = scraped_data.join(' - ')
            data << str
            data << 'EventTypeEnumeration'
            if str.scan(/\b(Young public|Jeune public)/i).present?
              data << ['ChildrensEvent', 'http://schema.org/ChildrensEvent']
            end
            if str.scan(/\b(Comedy|Humour)/i).present?
              data << ['ComedyEvent', 'http://schema.org/ComedyEvent']
            end
            if str.scan(/\b(Dance|Danse)/i).present?
              data << ['DanceEvent', 'http://schema.org/DanceEvent']
            end
            if str.scan(/\b(Music|Musique)/i).present?
              data << ['MusicEvent', 'http://schema.org/MusicEvent']
            end
            if str.scan(/\b(Theatre|Théâtre)/i).present?
              data << ['TheaterEvent', 'http://schema.org/TheaterEvent']
            end
          elsif property.uri == 'http://schema.org/eventAttendanceMode'
            str = scraped_data.join(' - ')
            data << str
            data << 'EventAttendanceModeEnumeration'
            if str.scan(/\b(OfflineEventAttendanceMode)/i).present?
              data << ['In-person', 'http://schema.org/OfflineEventAttendanceMode']
            end
            if str.scan(/\b(OnlineEventAttendanceMode)/i).present?
              data << ['Online', 'http://schema.org/OnlineEventAttendanceMode']
            end
            if str.scan(/\b(MixedEventAttendanceMode)/i).present?
              data << ['Mixed', 'http://schema.org/MixedEventAttendanceMode']
            end
          else
            if scraped_data.class == Array
              scraped_data.each do |uri_string|
                if uri_string.present? # Do not try to link URIs with empty strings
                  data << search_for_uri(uri_string, property, webpage)
                end
              end
            end
          end
        end
      end
    elsif property.value_datatype == 'xsd:duration'
      scraped_data.each do |t|
        data << ISO_duration(t)
      end
    else
      data = scraped_data
    end
    if data.class == Array
      data = data.first if data.count == 1
    end
    data
  end

  def search_for_uri(uri_string, property_obj, current_webpage)
    # data structure of uri = ['name', 'rdfs_class', ['name', 'uri'], ['name','uri'],...]
    uri_string = uri_string.to_s.squish

    uris = [uri_string]
    # use property object to determine class
    rdfs_class = property_obj.expected_class

    if rdfs_class.split(',').count > 1
      # there is a list of class types i.e. ["Place"," VirtualLocation"]
      # TODO: Fix to search for all types
      # Patch: for now take first expected class type only
      rdfs_class = rdfs_class.split(',').first
    end
    uris << rdfs_class

    #############################
    # search KG
    #############################
    cckg_results = search_cckg(uri_string, rdfs_class)

    if cckg_results[:error]
      logger.error("*** search kg ERROR:  #{cckg_results}")
      uris << 'abort_update' # this forces the update to skip when the KG server is down and avoids setting everything to blank
    else
      cckg_results[:data].each do |uri|
        uris << uri if uri
      end
    end

    if rdfs_class == 'Organization'
      cckg_results = search_cckg(uri_string, 'Person')
      if cckg_results[:error]
        logger.error("*** search kg ERROR:  #{cckg_results}")
        uris << 'abort_update' # this forces the update to skip when the KG server is down and avoids setting everything to blank
      else
        cckg_results[:data].each do |uri|
          uris << uri if uri
        end
      end
    end


    # When nothing is found in artsdata.ca CC KG then try locally
    if uris.count == 2  
      #############################
      # search Local Condenser DB
      #############################
      local_results = search_condenser(uri_string, rdfs_class)

      local_results[:data].each do |uri|
        if uri
          http_uri = uri[1].gsub('adr:', 'http://kg.artsdata.ca/resource/')
          uris << [uri[0], http_uri] if current_webpage.rdf_uri != uri[1]  # DO not add the URI of the current URI (can happen when adding sameAs)
        end
      end
    end

    uris.uniq!
    uris
  end

  def search_condenser(uri_string, expected_class) # returns a HASH
    # get names of all statements of expected_class
    hits = []
    # statements = Statement.where(cache: uri_string)
    entities = Statement.joins(source: :property).where(status: ['ok','updated']).where({ sources: { selected: true, properties: { label: 'Name', rdfs_class: RdfsClass.where(name: expected_class) } }  }).pluck(:cache, :webpage_id)
    entities.each do |entity|
      hits << entity if uri_string.downcase.include?(entity[0].downcase)
    end

    if expected_class == "Organization"
      entities = Statement.joins(source: :property).where(status: ['ok','updated']).where({ sources: { selected: true, properties: { label: 'Name', rdfs_class: RdfsClass.where(name: "Person") } } }).pluck(:cache, :webpage_id)
      entities.each do |entity|
        hits << entity if uri_string.downcase.include?(entity[0].downcase)
      end
    end

    # get uris
    hits.each_with_index do |hit, index|
      webpage = Webpage.find(hit[1])
      hits[index][1] = webpage.rdf_uri if webpage
    end
    
    #################################################
    # REMOVE NAMES THAT CREATE MANY FALSE POSITIVES - until better analysis with NLP is available
    names_to_remove = SearchException.where(rdfs_class: RdfsClass.where(name: expected_class)).pluck(:name)
    hits.reject! { |hit| names_to_remove.include? hit[0] }
    #################################################
    
    { data: hits.uniq }
    # #TODO: ????also check (s.webpage.website == webpage.website)
  end

  def search_cckg(str, rdfs_class) # returns a HASH
    if str.length > 3

      # call Reconciliation service
      results = HTTParty.get("https://api.artsdata.ca/recon?query=#{CGI.escape(CGI.unescapeHTML(str))}&type=#{rdfs_class}")

      if results.response.code == "200"
        # keep results that are matches
        hits = JSON.parse(results.response.body)
        hits = hits["result"].select { |h| h["match"] == true }.map { |h| [h["name"], "http://kg.artsdata.ca/resource/#{h["id"]}"]}
        hits.uniq! { |hit| hit[1] }

        #################################################
        # REMOVE NAMES THAT CREATE MANY FALSE POSITIVES - until better analysis with NLP is available
        names_to_remove = SearchException.where(rdfs_class: RdfsClass.where(name: rdfs_class)).pluck(:name)
        hits.reject! { |hit| names_to_remove.include? hit[0] }
        #################################################

        { data: hits }
      else
        { error: "#{results.response.code}: #{results.response.message}", method: 'search_cckg' } # with error message
      end
    else
      { error: "String '#{str} is too short. Needs to be londer than 2 characters", method: 'search_cckg' } # with error message
    end
  end

  def ISO_duration(duration_str)
    begin
      duration_in_seconds = ChronicDuration.parse(duration_str)
      duration_iso8601 = if duration_in_seconds.blank?
                           '' # Leave statement empty so it gets ignored in the triple store.
                         else
                           "PT#{duration_in_seconds}S"
                         end
    rescue StandardError
      duration_iso8601 = "Error in duration: #{duration_str}"
    end
    duration_iso8601
  end

  def french_to_english_month(date_time)
    date_time.downcase
             .gsub(/janvier|février|fév|mars|avr|mai|juin|juillet|juil|août|aou|aoû|septembre|octobre|novembre|décembre|déc/, 'janvier' => 'JAN', 'février' => 'FEB', 'fév' => 'FEB', 'mars' => 'MAR', 'avril' => 'APR', 'avr' => 'APR', 'mai' => 'MAY', 'juin' => 'JUN', 'juillet' => 'JUL', 'juil' => 'JUL', 'aou' => 'AUG', 'août' => 'AUG', 'aoû' => 'AUG', 'septembre' => 'SEP', 'octobre' => 'OCT', 'novembre' => 'NOV', 'décembre' => 'DEC', 'déc' => 'DEC')
  end

  def ISO_dateTime(date_time, time_zone = 'Eastern Time (US & Canada)')
    begin
      current_timezone = Time.zone
      Time.zone = time_zone
      d = Time.zone.parse(french_to_english_month(date_time)
                               .gsub(/ h /, 'h') # French times usually have spaces around the 'H'
                               .gsub(/halifax/i, '')) # Halifax is used in timezone names. Remove it to avoid confusion.

      # if the dateTime is midnight then assume that there is no known time and convert to a Date Object instead of Time object.
      d = d.to_date if d == d.midnight

      Time.zone = current_timezone

      iso_date_time = d.iso8601
    rescue StandardError => e
      iso_date_time = "Bad input for date/time: #{date_time}.  (#{e.inspect})"
    end
    iso_date_time
  end

  def format_language(language)
    '@' + language unless language.blank?
  end

  def build_key(statement) # for JSON output
    new_key = statement.source.property.label.downcase.sub(' ', '_')
    unless statement.source.language.blank?
      new_key = "#{new_key}_#{statement.source.language}"
    end
    new_key
  end

  def process_linked_data_removal(statement_cache, uri_to_delete, class_to_delete, label_to_delete)
    statement_cache = [statement_cache] if statement_cache[0].class != Array

    updated_cache = false
    statement_cache.each_with_index do |c, i|
      next unless c[0] == 'Manually deleted' || c[0] == 'Manually added'

      c.each_with_index do |uri_pair, x|
        if uri_pair[1] == uri_to_delete
          statement_cache[i].delete_at(x)
          updated_cache = true
        end
      end
      statement_cache.delete_at(i) if c.length < 3
    end

    # if no change then store the link to delete
    unless updated_cache

      link_added = false
      statement_cache.each_with_index do |c, i|
        if c[0] == 'Manually deleted'
          statement_cache[i] << [label_to_delete, uri_to_delete]
          link_added = true
        end
      end
      unless link_added
        statement_cache << ['Manually deleted', class_to_delete, [label_to_delete, uri_to_delete]]
      end

    end

    statement_cache
  end

  def preserve_manual_links _data, old_data
    _data = [_data] if _data[0].class != Array
    begin
      _old_cache = JSON.parse(old_data)
    rescue StandardError => e
      _old_cache = old_data
    end
    _old_cache = [_old_cache] if _old_cache[0].class != Array
    _old_cache.each do |c|
      _data << c if c[0] == 'Manually added' || c[0] == 'Manually deleted'
    end
    _data
  end
end
