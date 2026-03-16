# app/controllers/dashboard_metrics_controller.rb
class DashboardMetricsController < ApplicationController

  def index
    results = Rails.cache.fetch("dashboard_metrics", expires_in: 10.minutes) do
      compute_all_metrics
    end

    render json: results
  end

  def broken
    results = Rails.cache.fetch("dashboard_metrics", expires_in: 10.minutes) do
      compute_all_metrics
    end

    broken = results.select do |_seedurl, m|
      m[:new_webpages_7d].zero? &&
        m[:statements_updated_24hr].zero? &&
        m[:event_horizon_days].negative?
    end

    render json: broken
  end

  private

  def compute_all_metrics
    websites = Website.where(monitorable: true).pluck(:id, :seedurl)

    seedurls = websites.map { |(_, seedurl)| seedurl }

    website_ids = websites.to_h { |id, seedurl| [seedurl, id] }

    # ----------------------------
    # total webpages
    # ----------------------------

    event_webpages =
      Webpage.joins(:website)
             .where(websites: { monitorable: true })
             .where(rdfs_class_id: 1)
             .group("websites.seedurl")
             .count

    # ----------------------------
    # last webpage creation
    # ----------------------------

    last_webpages =
      Webpage.joins(:website)
             .where(websites: { monitorable: true })
             .where(rdfs_class_id: 1)
             .group("websites.seedurl")
             .maximum(:created_at)

    # ----------------------------
    # new webpages in last 7 days
    # ----------------------------

    new_webpages =
      Webpage.joins(:website)
             .where(websites: { monitorable: true })
             .where(rdfs_class_id: 1)
             .where("webpages.created_at >= ?", 7.days.ago)
             .group("websites.seedurl")
             .count

    # ----------------------------
    # publishable webpages
    # ----------------------------

    publishable_webpages =
      Statement.joins(webpage: :website)
               .joins(source: :property)
               .where(websites: { monitorable: true })
               .where(properties: { label: %w[Title Location Dates] })
               .where(status: %w[ok updated])
               .where(webpages: { rdfs_class_id: 1 })
               .group("websites.seedurl", "webpages.id")
               .having("COUNT(DISTINCT properties.label) = 3")
               .count
               .keys
               .map(&:first)
               .tally

    # ----------------------------
    # archive horizon
    # ----------------------------

    max_archive_dates =
      Webpage.joins(:website)
             .where(websites: { monitorable: true })
             .group("websites.seedurl")
             .maximum(:archive_date)

    # ----------------------------
    # statements grouped
    # ----------------------------

    statements_grouped =
      Statement.joins(webpage: :website)
               .where(websites: { monitorable: true })
               .group("websites.seedurl")
               .count

    # ----------------------------
    # refreshed last 24h
    # ----------------------------

    refreshed_24h =
      Statement.joins(webpage: :website)
               .where(websites: { monitorable: true })
               .where("statements.cache_refreshed >= ?", 24.hours.ago)
               .group("websites.seedurl")
               .count

    # ----------------------------
    # updated last 24h
    # ----------------------------

    updated_24h =
      Statement.joins(webpage: :website)
               .where(websites: { monitorable: true })
               .where("statements.cache_changed >= ?", 24.hours.ago)
               .group("websites.seedurl")
               .count

    # ----------------------------
    # last statement change
    # ----------------------------

    last_statement_change =
      Statement.joins(webpage: :website)
               .where(websites: { monitorable: true })
               .group("websites.seedurl")
               .maximum("statements.cache_changed")

    # ----------------------------
    # build result
    # ----------------------------

    seedurls.index_with do |seedurl|
      total_webpages = event_webpages[seedurl] || 0
      publishable = publishable_webpages[seedurl] || 0

      publishable_ratio =
        if total_webpages.zero?
          0
        else
          (publishable.to_f / total_webpages * 100).round(1)
        end

      archive = max_archive_dates[seedurl]

      horizon_days =
        if archive
          (archive.to_date - Time.zone.today).to_i
        else
          0
        end

      {
        website_id: website_ids[seedurl],
        total_webpages: total_webpages,
        publishable_ratio: publishable_ratio,
        statements_grouped: statements_grouped[seedurl] || 0,
        statements_refreshed_24hr: refreshed_24h[seedurl] || 0,
        statements_updated_24hr: updated_24h[seedurl] || 0,
        last_webpage_created_at: last_webpages[seedurl],
        last_statement_change: last_statement_change[seedurl],
        new_webpages_7d: new_webpages[seedurl] || 0,
        event_horizon_days: horizon_days
      }
    end
  end
end