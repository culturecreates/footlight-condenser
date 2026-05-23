module Distillator
  class TransitionEvidence < ApplicationRecord
    self.table_name = "distillator_transition_evidence"

    CHECK_KINDS = %w[fetch_parity statement_delta export_diff cache_key manual_acceptance].freeze
    STATUSES = %w[pending checked accepted rejected failed warning blocked].freeze

    belongs_to :website

    validates :url, presence: true
    validates :check_kind, presence: true, inclusion: { in: CHECK_KINDS }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :checked_at, presence: true

    scope :latest_first, -> { order(checked_at: :desc, id: :desc) }
    scope :for_website, ->(website) { where(website_id: website.is_a?(Website) ? website.id : website) }
    scope :for_kind, ->(check_kind) { where(check_kind: check_kind.to_s) }

    def self.latest_for_website(website, check_kind = nil)
      scope = for_website(website).latest_first
      scope = scope.for_kind(check_kind) if check_kind.present?
      scope.first
    end

    def self.latest_for_website_ids(website_ids)
      return {} if Array(website_ids).blank?

      rows = select("DISTINCT ON (website_id, check_kind) *")
        .where(website_id: Array(website_ids))
        .order(Arel.sql("website_id, check_kind, checked_at DESC, id DESC"))

      rows.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |row, grouped|
        grouped[row.website_id][row.check_kind] = row
      end
    end

    def export_diff_satisfied?
      export_diff_checked? || export_diff_accepted? || export_diff_status.to_s.in?(%w[checked accepted])
    end

    def export_diff_checked?
      export_diff_checked == true
    end

    def export_diff_accepted?
      export_diff_accepted == true
    end

    def representative_urls_checked?
      status.to_s.in?(%w[checked accepted]) || truthy_detail?("representative_urls_checked")
    end

    def acceptable_statement_delta?
      return statement_count_delta_acceptable if [true, false].include?(statement_count_delta_acceptable)

      truthy_detail?("statement_count_delta_acceptable")
    end

    def attempted_condenser_fetch?
      truthy_detail?("attempted_condenser_fetch")
    end

    def detail_reason
      details.to_h["reason"] || details.to_h[:reason]
    end

    private

    def truthy_detail?(key)
      value = details.to_h[key.to_s] || details.to_h[key.to_sym]
      value == true || value.to_s == "true" || value.to_s == "1"
    end
  end
end
