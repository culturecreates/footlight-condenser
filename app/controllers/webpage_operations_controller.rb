class WebpageOperationsController < ApplicationController
  before_action :set_webpage

  def refetch_source
    result = refetch
    if usable_source?(result)
      finish(notice: "Source refetched. Statement results were kept.")
    else
      finish(alert: (result[:refetch_error] || "Source refetch failed. See the latest fetch attempt in Source and extraction."))
    end
  end

  def refresh_statements
    forced = params[:refetch] == "true"
    if forced
      result = refetch
      unless usable_source?(result)
        message = result[:refetch_error] || "Source refetch failed."
        return finish(alert: "#{message} Statement extraction did not run.")
      end
    end

    page_fetch = extraction_page_fetch
    errors = refresh_service.call(webpage: @webpage, default_language: @webpage.website.default_language,
      sources: sources, page_fetch: page_fetch)
    primary = page_fetch.result&.fetch(:fetch_provenance, nil)
    input = case primary&.fetch(:usage, nil)
    when "cached" then "The primary source came from Condenser’s cache."
    when "fetched"
      if primary[:backend] == "legacy"
        "Condenser fetched the primary response through Wringer. Upstream cache reuse is unknown."
      else
        "The primary source was fetched."
      end
    else "No primary source response was used or recorded. The DSL may use other inputs."
    end
    if errors.any?
      finish(alert: "Statement extraction reported #{helpers.pluralize(errors.size, 'error')}. #{input}")
    else
      finish(notice: "Statement refresh completed. #{input}")
    end
  end

  def reconcile_urls
    created = @webpage.with_lock do
      snapshot = Distillator::TransitionEventInventory.new(as_of: Time.current).snapshot_for(@webpage)
      unless @webpage.rdfs_class&.name == "ResourceList" && snapshot[:status] == "event"
        reason = snapshot[:extraction_reason] || snapshot[:reason] || :other_class
        return finish(alert: Distillator::ResourceListReadiness.guidance(reason).fetch(:message))
      end

      AddWebpagesJob.perform_now(@webpage.id, selected_only: true, refresh_new: false,
        expected_discovery: { website_id: @webpage.discovery_target_website_id || @webpage.website_id,
          contents_digest: snapshot.fetch(:contents_digest) })
    end
    message = created.empty? ? "Discovery complete. No new webpages to create." : "Imported #{helpers.pluralize(created.size, 'new webpage')}."
    finish(notice: message)
  rescue AddWebpagesJob::InvalidResourceListError
    finish(alert: "The ResourceList changed during reconciliation. Verify its statements and try again.")
  end

  private

  def set_webpage
    @webpage = Webpage.find(params[:id])
  end

  def refresh_service
    @refresh_service ||= Statements::RefreshWebpageStatementsService.new(
      refresh_helper: StatementsHelper.build_refresh_proxy(context: helpers, cookies: request.cookies.with_indifferent_access, logger: logger)
    )
  end

  def sources
    @sources ||= Statements::RefreshWebpageStatementsService.sources_for_webpage(@webpage,
      default_language: @webpage.website.default_language)
  end

  def extraction_page_fetch
    @page_fetch ||= Statements::PageFetch.new(render_js: sources.any?(&:render_js?), scrape_options: {})
  end

  def refetch
    unless @webpage.url.to_s.match?(%r{\Ahttps?://}i) && Distillator::FetchGuard.check_url(@webpage.url).allowed?
      return { status: :abort, refetch_error: "This webpage does not have an allowed HTTP source URL." }
    end

    Dsl::Core::AlgorithmRunner.new(url: @webpage.url, tracer: Dsl::Tracing::NullTracer.new, scrape_options: {
      force_scrape: true, website: @webpage.website, page_fetch: extraction_page_fetch
    }).refetch_source
  rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
    { status: :abort, refetch_error: "The source URL is invalid." }
  end

  def usable_source?(result)
    result[:status] == :ok && result[:body].is_a?(String) && result[:body].present?
  end

  def finish(**flash)
    redirect_to webpage_path(@webpage, return_to: safe_return_to_param, anchor: "webpage-source-extraction"),
      status: :see_other, **flash
  end
end
