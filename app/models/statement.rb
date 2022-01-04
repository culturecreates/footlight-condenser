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

  # For pagination
  self.per_page = 100

  def check_if_cache_changed
    return unless changed_attributes[:cache].present?

    # Check 'xsd:anyURI' datatypes for a change in URIs
    # Changes in URI search strings should not count as a change
    @value_datatype ||= source.property.value_datatype
    if @value_datatype == 'xsd:anyURI'
      previous_uris = JsonUriWrapper.extract_uris_from_cache(changed_attributes[:cache])
      
      new_uris = JsonUriWrapper.extract_uris_from_cache(cache)
      return if previous_uris.sort == new_uris.sort
    end

    self.cache_changed = Time.new

    # Set status to updated unless in intial state.
    # because status cannot update itself from initial state. Need a human to see it first.
    unless status == 'initial' && status_origin == 'condenser_refresh'
      self.status = 'updated'
    end
    self.status_origin = 'condenser_refresh'

  end

  # update status of mandatory properties
  def check_mandatory_properties
    return if status == 'problem' || status == 'intial'

    property_label = source.property.label

    if property_label == 'Location'
      urls = JsonUriWrapper.extract_uris_from_cache(cache)
      self.status = 'missing' unless urls.to_s.include?('http')
    elsif property_label == 'Dates'
      self.status = 'missing' unless valid_date?
    elsif property_label == 'Title'
      self.status = 'missing' unless cache.present?
    elsif property_label == 'Virtual Location'
      self.status = 'missing' unless cache.present?
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
  # and when the statement is selected individually or as the source selection
  def update_archive_date
    return unless selected_individual

    return if cache.include?('error') || cache.include?('bad')

    @value_datatype ||= source.property.value_datatype
    if @value_datatype == 'xsd:dateTime' || @value_datatype == 'xsd:date'
     
      return unless valid_date?

      last_show_date = last_show_date(cache)
      
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
end
