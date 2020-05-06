class Statement < ApplicationRecord
  belongs_to :source
  belongs_to :webpage

  validates :source, uniqueness: { scope: :webpage }

  # for pagination
  self.per_page = 100

  STATUSES = {
    initial: 'Initial',
    missing: 'Missing',
    ok: 'Ok',
    problem: 'Problem',
    updated: 'Updated'
  }.freeze

  validates :status, inclusion: { in: STATUSES.keys.map(&:to_s) }

  STATUSES.keys.each do |type|
    define_method("is_#{type}?") { self.status == type.to_s }
    scope type, -> { where(status: type) }
    self.const_set(type.upcase, type)
  end

  before_save :set_cache_changed
  before_save :check_mandatory_properties

  def set_cache_changed
    return unless self.changed_attributes[:cache].present?

    self.cache_changed = Time.new
    unless self.status == "initial" && self.status_origin == "condenser_refresh"
      # condenser cannot update inself from initial to update state. Need a human to have seen it first.
      self.status = "updated"
    end
    self.status_origin = "condenser_refresh"
  end

  # check for mandatory properties unless status is already a problem
  def check_mandatory_properties
    return if status == 'problem'

    property_label = source.property.label
    if property_label == 'Location'
      self.status = 'missing' unless cache.include?('http')
    elsif property_label == 'Dates'
      self.status = 'missing' unless valid_date?
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
    if date_array.select { |d| d if valid_iso_date?(d) }.count > 0
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
end
