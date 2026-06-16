class WringerCompatibilityController < ApplicationController
  def show
    response.headers.delete "X-Frame-Options"
    return invalid_response unless params[:uri].present?

    cache = Distillator::FetchCacheStore.fetch(
      uri: params[:uri],
      include_fragment: Distillator::BooleanParam.parse(params[:include_fragment]),
      force_scrape: Distillator::BooleanParam.parse(params[:force_scrape]),
      force_scrape_every_hrs: params[:force_scrape_every_hrs],
      use_phantomjs: use_phantomjs_param,
      absolute_src: Distillator::BooleanParam.parse(params[:absolute_src]),
      json_post: Distillator::BooleanParam.parse(params[:json_post]),
      mode: :internal
    )

    case params[:format].to_s
    when "raw"
      render html: (cache.html || "").html_safe
    when "json"
      render json: {
        html: cache.html,
        signals: cache.signals || {},
        hints: cache.hints || [],
        final_url: cache.final_url,
        redirect_chain: cache.redirect_chain || [],
        http_code: cache.http_response_code
      }
    else
      redirect_to websites_path, notice: "Website was successfully wrung."
    end
  rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
    invalid_response
  end

  private

  def use_phantomjs_param
    return true if uri_key.uri_key.end_with?("iframe")

    Distillator::BooleanParam.parse(params[:use_phantomjs])
  end

  def uri_key
    @uri_key ||= Distillator::WringerUrlKey.call(
      params[:uri],
      include_fragment: Distillator::BooleanParam.parse(params[:include_fragment])
    )
  end

  def invalid_response
    return redirect_to(websites_path, notice: "INVALID params for wringing.") if params[:format].to_s == "html"

    head :no_content
  end
end
