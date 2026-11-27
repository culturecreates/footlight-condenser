module MonitoringHelper
  def monitoring_issue_website(issue, targets)
    websites = targets.fetch(:websites).fetch(issue.seedurl, [])
    return websites.first if websites.one?

    exact_matches = websites.select { |website| website.name == issue.website_name }
    exact_matches.first if exact_matches.one?
  end

  def monitoring_issue_category(issue)
    issue.category_label
  end

  def monitoring_issue_actions(issue, targets)
    links = []
    if targets.fetch(:webpages).include?(issue.webpage_id)
      links << ["Inspect webpage", webpage_path(issue.webpage_id)]
    end
    if issue.kind == "blocked_fetch" && external_http_url?(issue.url)
      links << ["Inspect fetch cache", distillator_cache_index_path(term: issue.url)]
    end
    if targets.fetch(:policies).include?(issue.preprocessing_policy_id)
      links << ["Inspect policy", edit_preprocessing_policy_path(issue.preprocessing_policy_id)]
    end
    if targets.fetch(:statements).include?(issue.statement_id)
      links << ["Inspect statement", statement_path(issue.statement_id)]
    end
    if targets.fetch(:sources).include?(issue.source_id)
      links << ["Inspect source", source_path(issue.source_id)]
    end
    links
  end
end
