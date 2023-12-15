class Statement < ApplicationRecord
  belongs_to :source
  belongs_to :webpage

  STATUSES = {
    initial: 'Initial',
    missing: 'Missing',
    ok: 'Ok',
    problem: 'Problem',
    updated: 'Updated'
  }.freeze

  STATUSES.keys.each do |type|
    define_method("is_#{type}?") { status == type.to_s }
    scope type, -> { where(status: type) }
    const_set(type.upcase, type)
  end

  validates :source, uniqueness: { scope: :webpage }
  validates :status, inclusion: { in: STATUSES.keys.map(&:to_s) }
  before_save :check_if_cache_changed
  before_save :check_mandatory_properties
  before_save :update_archive_date
  before_save :set_manual_performer_organizer
  before_save :check_no_abort_update
  before_save :check_for_invalid_price

  # For pagination
  self.per_page = 100

  def check_if_cache_changed
    return unless changed_attributes[:cache].present?  || self.status == 'missing' 
    
    # Check 'xsd:anyURI' datatypes for a change in URIs
    # Changes in URI search strings should not count as a change
    @value_datatype ||= source.property.value_datatype
    if @value_datatype == 'xsd:anyURI'

      previous_uris = if changed_attributes[:cache] 
                        JsonUriWrapper.extract_uris_from_cache(changed_attributes[:cache])
                      end
      
      new_uris = JsonUriWrapper.extract_uris_from_cache(cache)
      return if previous_uris&.sort == new_uris&.sort
    end

    self.cache_changed = Time.new

    # Set status to updated unless in intial state.
    # because status cannot update itself from initial state. Need a human to see it first.
    unless  self.status == 'initial' &&  self.status_origin == 'condenser_refresh'
      self.status = 'updated'
    end
    self.status_origin = 'condenser_refresh'

  end

  # update status of mandatory properties
  def check_mandatory_properties
    return if  self.status == 'problem' ||  self.status == 'intial'

    @property_label ||= source.property.label
    if @property_label == 'Location'
      self.status = 'missing' if JsonUriWrapper.check_for_multiple_missing_links(cache) 
    elsif @property_label == 'Dates'
      self.status = 'missing' unless valid_date?
    elsif @property_label == 'Title'
      self.status = 'missing' unless cache.present?
    elsif @property_label == 'VirtualLocation'
      self.status = 'missing' unless (cache.present? && cache != '[]')
    end
  end

  def check_no_abort_update
    self.status = 'problem' if cache.include?('abort_update') if cache
  end

  def check_for_invalid_price 
    return if self.status == 'problem'
    @property_label ||= source.property.label
    if ['Price'].include?(@property_label)
      self.status = 'problem' if !self.integer_or_float?(cache)
    end
  end

  def set_manual_performer_organizer
    return if self.manual

    return if self.status == 'problem' ||  self.status == 'initial'

    @property_label ||= source.property.label
    if ['Performed by','Organized by'].include?(@property_label)
      if changed_attributes != {"manual"=>true} # Only change allowed is to remove manual setting
        self.manual = true
      end
    end
  end

  def valid_date?
    begin
      date_array = JSON.parse(cache)
    rescue JSON::ParserError
      # convert string to array
      date_array = Array(cache)
    end
    # look for valid dates in array
    if date_array.select { |d| d if valid_iso_date?(d) }.count.positive?
      true
    else
      false
    end
  end

  def valid_iso_date?(date_string)
    begin
      Date.iso8601(date_string)
      true
    rescue ArgumentError
      false
    end
  end

  def last_show_date(date_string)
    begin
      # convert string to array
      date_array = JSON.parse(cache)
    rescue JSON::ParserError
      # add string to array
      date_array = Array(cache)
    end
    # keep only valid dates in array
    date_array.select! { |d| d if valid_iso_date?(d) }
    # return the last date
    date_array.sort.last
  end

  # Set the archive date whenever the startDate or endDate cache changes
  # including when the statement is manually edited
  def update_archive_date
    return unless selected_individual

    @property_uri ||= source.property.uri
    if @property_uri.include?('startDate') || @property_uri.include?('endDate')
      return if cache.nil?

      return if cache.include?('error') || cache.include?('bad')

      last_show_date = last_show_date(cache)
      if last_show_date.present?
        # Get all webpage languages
        webpages = Webpage.where(rdf_uri: webpage.rdf_uri)
        webpages.update_all(archive_date: last_show_date.to_datetime - 24.hours)
        logger.debug("*** set archive date for #{webpage.rdf_uri} to #{webpage.archive_date}")
      end
    end
  end


  # Check that the scrapped string/array can be converted to one or more integers or floats.
  def integer_or_float?(str)
    price_list = convert_array(str).reject {|p| p.blank?}
    price_list.each do |price|
      begin 
        !!Float(price)  #-> this is a string that is forced into a boolean 
        #   context (true), and then negated (false), and then 
        #   negated again (true)
      rescue 
        return false 
      end
    end
  end

  # ensure we have an Array so we can iterate
  def convert_array(str)
    return str if str.class == Array
    begin [*JSON[str]] rescue Array(str) end
  end


end
