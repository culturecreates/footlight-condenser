class Statement < ApplicationRecord
  belongs_to :source
  belongs_to :webpage

  validates :source, uniqueness: { scope: :webpage }

  STATUSES = { initial: 'Initial', missing: 'Missing', ok: 'Ok', problem: 'Problem',updated: 'Upated' }
  validates :status, inclusion: { in: STATUSES.keys.map(&:to_s) }

  STATUSES.keys.each do |type|
    define_method("is_#{type}?") { self.status == type.to_s }
    scope type, -> { where(status: type) }
    self.const_set(type.upcase, type)
  end

  def save
    if !self.changed_attributes[:cache].nil?
      self.cache_changed = Time.new
      self.status = "updated"
      self.status_origin = "condensor_refresh"
    end

    super
  end


end
