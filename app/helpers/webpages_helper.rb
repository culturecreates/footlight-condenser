# Helper used in mulitple places
module WebpagesHelper
  include ApplicationHelper

  # Check for missing required properties
  # TODO: replace this with SHACL
  def missing_required_properties(event_statement_collection)
    # receive a set of statements for an event and check if the event is publishable
    mandatory_schema = ["http://schema.org/name", "http://schema.org/startDate", "http://schema.org/location"]
    problem_statements = event_statement_collection.select{ |s| s[:rdfs_class_name] == "Event" && mandatory_schema.include?(s[:predicate]) && (( s['status'] != "ok" && s['status']  != "updated")  || s[:value] == "[]" ||  s[:value].blank? ) }

    # Virtual Location removes location error if valid
    if event_statement_collection.select { |s| s[:label] == "VirtualLocation" && (( s['status'] == "ok" || s['status']  == "updated")  && s[:value] != "[]" &&  s[:value].present? )}.count > 0
      problem_statements.reject! { |s| s[:predicate] == "http://schema.org/location" }
    end

    problem_statements
  end

  def webpage_cache_links(webpage)
    active_cache_links_for(webpage.url, website: webpage.website)
  end

  def webpage_rollout_badge(webpage)
    operator_rollout_badge(webpage.website)
  end

  def webpage_rollout_explanation(webpage)
    operator_rollout_explanation(webpage.website)
  end

  def webpage_rollout_label_for(webpage)
    Distillator::RolloutCopy.label(webpage&.website&.distillator_mode)
  end

  def webpage_rollout_backend_for(webpage)
    operator_active_backend_label(webpage.website)
  end

  def webpage_rollout_next_step_for(webpage)
    operator_rollout_next_step(webpage.website)
  end
end
