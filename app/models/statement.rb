class Statement < ApplicationRecord
  belongs_to :source
  belongs_to :webpage

  validates :source, uniqueness: { scope: :webpage }

  # for pagination
  self.per_page = 100

 

  STATUSES = { initial: 'Initial', missing: 'Missing', ok: 'Ok', problem: 'Problem',updated: 'Updated' }
  validates :status, inclusion: { in: STATUSES.keys.map(&:to_s) }

  STATUSES.keys.each do |type|
    define_method("is_#{type}?") { self.status == type.to_s }
    scope type, -> { where(status: type) }
    self.const_set(type.upcase, type)
  end

  def save
    if !self.changed_attributes[:cache].nil?
      self.cache_changed = Time.new
      if self.status != "initial" && self.status_origin != "condenser_refresh"
        # condenser cannot update inself from initial to update state. Need a human to have seen it first.
        self.status = "updated"
      end
      self.status_origin = "condenser_refresh"
    end

    super
  end


end
