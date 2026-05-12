module Distillator
  class FetchCache < ApplicationRecord
    self.table_name = "distillator_fetch_caches"

    validates :uri_key, presence: true, uniqueness: true

    before_save :materialize_health_fields

    scope :with_issue_key, ->(key) { where(primary_issue_key: key) }
    scope :delete_candidates, -> { where(delete_candidate: true) }

    private

    def materialize_health_fields
      Distillator::CacheHealthMaterializer.call(self)
    end
  end
end
