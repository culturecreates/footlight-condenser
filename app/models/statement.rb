class Statement < ApplicationRecord
  belongs_to :source
  belongs_to :webpage

  validates :source, uniqueness: { scope: :webpage }

  def save
    if !self.changed_attributes[:cache].nil?
      self.cache_changed = Time.new
    end

    super
  end


end
