# frozen_string_literal: true

module StatementsHelper
  include CcKgHelper
  include CcWringerHelper
  Page = Struct.new(:text) # Used to simulate Nokogiri object's text method

  ##
  # Refresh a statement
  #   INPUT
  #   stat = ActiveRecord Statement 
  #   scrape_options = {} passesd on to footlight-wringer crawling service in process_algorithm
  #   OUTPUT
  #   Persists statement in database or sets errors. 
  #   Check stat.errors in calling method.
  def refresh_statement_helper(stat, scrape_options = {})
    if stat.manual && ["ok","updated"].include?(stat.status)
      stat.errors.add(:manual, message: "No update unless 'initial' state.")
      return
    end

    data = process_algorithm(algorithm: stat.source.algorithm_value, render_js: stat.source.render_js, language:stat.source.language, url: stat.webpage.url, scrape_options: scrape_options)
    data = format_datatype(data, stat.source.property, stat.webpage)

    save_record = false
    if data&.to_s&.include?('abort_update')
      stat.errors.add(:scrape, message: data)
    elsif data.blank?
      if !stat.new_record?
        stat.errors.add(:blank_detected, message: "No update: '#{data}'")
      end
    else
      save_record = true
      if stat.cache.present?
        if stat.source.property.value_datatype == 'xsd:anyURI'
          data = preserve_manual_links(data, stat.cache)
        end
      end
    end
    if save_record || stat.new_record?
      stat.cache = data
      stat.cache_refreshed = Time.new
      stat.save
    end
  end


  ##
  # Process alorithm for a statement
  # INPUTS
  #   statement.source.algorithm
  #   statement.source.render_js
  #   statement.webpage.language - language of website set in condenser, not source language which is optional
  #   statement.webpage.url
  #   scrape_options - passed on to footlight-wringer scraping service. 
  #   statement.cache_refreshed - cache refreshed, lastCrawledAt, schema:lastReview
  #   statement.cache_changed - cache changed, date modified, schema:sdDatePublished
  # OUTPUT
  #   [results] array
  #   Algorithms that generate an error (i.e. ruby syntax) return ["abort_update", {error: e.inspect, results_prior: results_list, algorithm_rescued: a}
  def process_algorithm(algorithm:, render_js: false, language: "en", url:, scrape_options: {}) #, cache_refreshed:, cache_changed:)
    if algorithm.start_with?('manual=')
      results_list = [algorithm.delete_prefix('manual=')]
    else
      agent = Mechanize.new
      agent.user_agent_alias = 'Mac Safari'
      html = nil
      page = nil
      json_scraped = nil # needed for case with ruby using $json in eval with 'json_scraped' scope
      results_list = []
      substitue_vars = lambda { |s| s.gsub('$array', 'results_list').gsub('$url', 'url').gsub('$json', 'json_scraped')}
      algorithm.split(";").each do |a|
        algo_type = a.partition('=').first
        algo = a.partition('=').last
        begin
          case algo_type 
          when "url"
            # replace current page by scraping new url
            # using format url='http://example.com' or ruby like url=$url + '.json'
            new_url = eval(substitue_vars.call(algo))
            logger.info "*** New URL formed: #{new_url}"
            html = agent.get_file(use_wringer(new_url, render_js, scrape_options))
            page = Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
          when 'renderjs_url'
            # FORCE Render JS -- replace current page by scraping new url with wringer
            # using format renderjs_url='http://example.com'
            new_url =  eval(substitue_vars.call(algo))
            logger.info "*** New URL formed: #{new_url}"
            html = agent.get_file(use_wringer(new_url, true, scrape_options))
            page = Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
          when 'json_url'
            new_url =  eval(substitue_vars.call(algo))
            logger.info "*** New URL for JSON call: #{new_url}"
            html = agent.get_file(use_wringer(new_url, render_js, scrape_options))
            page = Page.new(html)  # Do not use Nokogiri because it will remove html TODO: move struct down here
          when 'post_url'
            # replace current page data by scraping new url with wringer using POST
            # using format url='http://example.com?param_for_post='
            new_url =  eval(substitue_vars.call(algo))
            logger.info "*** New POST URL formed: #{new_url}"
            temp_scrape_options = scrape_options.merge(json_post: true)
            data = agent.get_file use_wringer(new_url, render_js, temp_scrape_options)
            page = Nokogiri::HTML(data)
          when 'api' # ok
            # Call API without going through wringer
            new_url =  eval(substitue_vars.call(algo))
            logger.info "*** New json api URL formed: #{new_url}"
            data = HTTParty.get(new_url)
            logger.info "*** api response body: #{data.body}"
            results_list = JSON.parse(data.body)
          when 'ruby' # test
            # Use ruby to process a var
            # ruby=$array.map{} or ruby=$json['name']
            results_list = eval(substitue_vars.call(algo))
          when 'xpath_sanitize' # ok
            html ||= agent.get_file(use_wringer(url, render_js, scrape_options))
            page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
            page_data = page.xpath(algo)
            page_data.each { |d| results_list << sanitize(d.to_s, tags: %w[h1 h2 h3 h4 h5 h6 p li ul ol strong em a i br], attributes: %w[href]) }
          when 'if_xpath' # continue if xpath resolves
            html ||= agent.get_file(use_wringer(url, render_js, scrape_options))
            page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
            page_data = page.xpath(algo)
            break if page_data.blank?
            page_data.each { |d| results_list << d.text }
          when 'unless_xpath' # continue unless xpath resolves
            html ||= agent.get_file(use_wringer(url, render_js, scrape_options))
            page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
            page_data = page.xpath(algo)
            break if page_data.present?
          when 'xpath' # test
            html ||= agent.get_file(use_wringer(url, render_js, scrape_options))
            # TODO: If response type is json then load json, otherwise load html in next line
            page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
            page_data = page.xpath(algo)
            page_data.each { |d| results_list << d.text }
          when 'css' # ok
            html ||= agent.get_file(use_wringer(url, render_js, scrape_options))
            page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
            page_data = page.css(algo)
            page_data.each { |d| results_list << d.text }
          when 'time_zone' # test
            results_list << "time_zone: #{algo}"
            logger.info "*** Adding time_zone: #{algo}"
          when 'json' # ok
            ## use this pattern in source algorithm --> json=$json['name']
            html ||= agent.get_file(use_wringer(url, render_js, scrape_options))
            page ||= Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
            json_scraped = JSON.parse(page.text)
            algo.gsub!('$json', 'json_scraped')
            results_list << eval(algo)
          else 
            results_list << ['abort_update',{error: "Missing valid prefix", algorithm: a}]
          end
        rescue SyntaxError => e
          return ['abort_update', {error: e.message.squish, error_type: e.class, results_prior: results_list, algorithm_rescued: a}]
        rescue  => e
          logger.error(" ****************** Error in scrape: #{e.inspect}")
          return ['abort_update', {error: e.inspect, error_type: e.class, results_prior: results_list, algorithm_rescued: a}]
        end
      end
    end
    results_list 
  end


  def scrape(source, url, scrape_options = {})
    process_algorithm(algorithm: source.algorithm_value, render_js:source.render_js, language:source.language, url:url, scrape_options: scrape_options) #, cache_refreshed:, cache_changed:)
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
    scraped_data = Array(scraped_data)
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
    data.uniq!
    data
  end

  def convert_date(scraped_data)
    dates = convert_datetime(scraped_data)
    dates.map do |d|
      begin
        d.to_date 
      rescue => exception
        "input: #{scraped_data} error: #{exception}"
      end
    end
  end

  def format_datatype(scraped_data, property, webpage, statement_status: "initial")
    data = []
    if property.value_datatype == 'xsd:dateTime'
      data = convert_datetime(scraped_data)
    elsif property.value_datatype == 'xsd:date'
      data = convert_date(scraped_data)
    elsif property.value_datatype == 'xsd:anyURI'
      unless scraped_data.blank?
        if property.expected_class == 'EventStatusType'
          data << reconcile_event_status(scraped_data)
        elsif property.expected_class == 'EventTypeEnumeration'
          data << reconcile_additional_type(scraped_data)
        elsif property.expected_class == 'EventAttendanceModeEnumeration'
          data << reconcile_attendance_mode(scraped_data)
        else
          if scraped_data.class == Array
            # Always reconcile when the state is "initial","missing","problem"
            # If the state is "ok", "update" then reconcile except performer and organizer.
            # Example: Performer that has been reviewed (ok) will not be reconciled.
           # if ["initial","missing","problem"].include?(statement_status) || !['http://schema.org/performer','http://schema.org/organizer'].include?(property.uri) 
              scraped_data.each do |uri_string|
                if uri_string.present? && !uri_string.include?("error:")# Do not try to link URIs with empty strings or errors
                  # TODO: Only reconcile location if original cache "based on:" text changed
                  data << search_for_uri(uri_string, property, webpage)
                end
              end
            # end
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

  def reconcile_event_status(scraped_data)
    str = scraped_data.join(' - ')
    result = [str, 'EventStatusType']
    if str.scan(/\b(Cancelled|Annulé|Annule)/i).present?
      result << ['EventCancelled', 'http://schema.org/EventCancelled']
    elsif str.scan(/\b(Postponed|Suspendu)/i).present?
      result << ['EventPostponed','http://schema.org/EventPostponed']
    elsif str.scan(/\b(Rescheduled|reporté|reporte)/i).present?
      result << ['EventRescheduled','http://schema.org/EventRescheduled']
    else
      result << ['EventScheduled','http://schema.org/EventScheduled']
    end
    result
  end

  def reconcile_additional_type(scraped_data)
    str = scraped_data.join(' - ')
    result =  [str, 'EventTypeEnumeration']
    if str.scan(/\b(Young public|Jeune public)/i).present?
      result << ['ChildrensEvent', 'http://schema.org/ChildrensEvent']
    end
    if str.scan(/\b(Comedy|Humour)/i).present?
      result << ['ComedyEvent', 'http://schema.org/ComedyEvent']
    end
    if str.scan(/\b(Dance|Danse)/i).present?
      result << ['DanceEvent', 'http://schema.org/DanceEvent']
    end
    if str.scan(/\b(Music|Musique|Chanson)/i).present?
      result <<  ['MusicEvent', 'http://schema.org/MusicEvent']
    end
    if str.scan(/\b(Theatre|Théâtre)/i).present?
      result << ['TheaterEvent', 'http://schema.org/TheaterEvent']
    end
    if str.scan(/\b(Screening|Movie|Cinéma)/i).present?
      result << ['TheaterEvent', 'http://schema.org/ScreeningEvent']
    end
    if str.scan(/\b(Performance)/i).present?
      result << ['Performance', 'http://ontology.artsdata.ca/Performance']
    end
    result
  end

  def reconcile_attendance_mode(scraped_data)
    str = scraped_data.join(' - ')
    result =  [str, 'EventAttendanceModeEnumeration']
    if str.scan(/\b(OfflineEventAttendanceMode)/i).present?
      result << ['In-person', 'http://schema.org/OfflineEventAttendanceMode']
    end
    if str.scan(/\b(OnlineEventAttendanceMode)/i).present?
      result << ['Online', 'http://schema.org/OnlineEventAttendanceMode']
    end
    if str.scan(/\b(MixedEventAttendanceMode)/i).present?
      result << ['Mixed', 'http://schema.org/MixedEventAttendanceMode']
    end
    result
  end



  def search_for_uri(uri_string, property_obj, current_webpage)
    # data structure of uri = ['name', 'rdfs_class', ['name', 'uri'], ['name','uri'],...]
    # use property object to determine class
    rdfs_class = property_obj.expected_class

    if rdfs_class.split(',').count > 1
      # there is a list of class types i.e. ["Place"," VirtualLocation"]
      # TODO: Fix to search for all types
      # Patch: for now take first expected class type only
      rdfs_class = rdfs_class.split(',').first
    end
    uris = search_everywhere(uri_string,rdfs_class)
    
    # DO not add the URI of the current URI (can happen when adding sameAs)
    uris[2..-1].select { |uri| uri unless uri[1] == current_webpage.rdf_uri }
    
    uris
  end

  # Used when refreshing and also when manually adding in Console
  def search_everywhere(uri_string,rdfs_class)
    uri_string = uri_string.to_s.squish
    uris = [uri_string]
    uris << rdfs_class

    #############################
    # search Local Condenser DB
    #############################
    local_results = search_condenser(uri_string, rdfs_class)

    local_results[:data].each do |uri|
      if uri
        http_uri = uri[1].gsub('adr:', 'http://kg.artsdata.ca/resource/')
        uris << [uri[0], http_uri]
      end
    end

    # When nothing is found locally then search in artsdata.ca CC KG 
    if uris.count == 2  
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
    end

    uris.uniq!
    uris
  end

  ####
  # hits = Statement.joins(source: :property)
  # .where(status: ['ok','updated'])
  # .where("lower(cache) LIKE ?", "%" + params[:query].downcase + "%")
  # .where({ sources: { selected: true, properties: { label: ['Name','alternateName'], rdfs_class: RdfsClass.where(name: params[:type]) } }  })
  # .distinct
  # .pluck(:cache, :webpage_id)

  def search_condenser(uri_string, expected_class) # returns a HASH
    # get names of all statements of expected_class

    if expected_class == "Organization"
      expected_class = ['Organization','Person']
    end

    hits = Statement.joins(source: :property)
                        .where(status: ['ok','updated'])
                        .where("lower(cache) LIKE ?", "#{uri_string.downcase}")
                        .where({ sources: { selected: true, properties: { label: ['Name','alternateName'], rdfs_class: RdfsClass.where(name: expected_class) } }  })
                        .pluck(:cache, :webpage_id)

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

      # setup recon variables
      recon_type =  if rdfs_class == "EventType"
                      "ado:EventType"
                    else
                      rdfs_class
                    end

      # call Reconciliation service
      begin
        results = HTTParty.get("#{artsdata_recon_url}?query=#{CGI.escape(CGI.unescapeHTML(str))}&type=#{recon_type}")
      rescue StandardError => e
        results = { error: "No server running at #{artsdata_recon_url}", method: 'search_cckg', message: "#{e.inspect}"}
        return results
      end

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
    rescue NoMethodError => e
      iso_date_time = ""
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

  def artsdata_recon_url
    if Rails.env.development?  || Rails.env.test?
      "http://localhost:#{ARTSDATA_API_PORT}/recon"
    else
      'http://api.artsdata.ca/recon'
    end
  end



  # Activate statement's source and selected_indvidual across all events
  # INPUT: statement ActiveRecord
  # OUPUT: sources ActiveRecord::Relation
  def activate_source(statement)
    #get all statements about this property/language for the resource(individual)
    
    sources = Source.where(website_id: statement.webpage.website.id, property_id: statement.source.property.id, language: statement.source.language )

    sources.each do |source|
      if source.id != statement.source.id
        if source.selected 
          source.update(selected: false)
          Statement.where(source: source, selected_individual: true)  
                   .update_all(selected_individual: false) # turn off all statements that were on by template
        end
      else # the one to activate
        source.update(selected: true)
        Statement.includes(:source)
                  .where(source: source, selected_individual: false)  # get all statements where currently 
                  .update_all(selected_individual: true)
      end
    end
    # Fix manual overrides
    override_statements = Statement.includes(:source).where(source: sources, sources: {selected: false}, selected_individual: true )
    
    override_statements.each do |s|
      # get other statements for same property/language/webpage
      related_statements = Statement.includes(:source).where(webpage_id: s.webpage_id, sources: { property_id: s.source.property.id, language: s.source.language})
      related_statements.each do  |related_stat|
        if related_stat.id != s.id
          related_stat.update(selected_individual: false)
        end
      end
    end

    sources
  end

  # def logger
  #  @logger ||= Logger.new(STDOUT)
  # end
end
