require "test_helper"

class Distillator::WringerRulesTest < ActiveSupport::TestCase
  setup do
    Distillator::WringerRules.reset!
  end

  teardown do
    Distillator::WringerRules.reset!
  end

  test "loads rules in declared yaml order" do
    keys = Distillator::WringerRules.all.map(&:first)

    assert_operator keys.index("cloudflare"), :<, keys.index("empty_body")
    assert_operator keys.index("queue_it"), :<, keys.index("http_403")
    assert_operator keys.index("akamai_bot_protection"), :<, keys.index("http_5xx")
    assert_operator keys.index("redirect_to_listing"), :<, keys.index("http_404")
  end

  test "all rules include match policy and ui metadata" do
    Distillator::WringerRules.all.each do |key, rule|
      assert rule["match"].present?, "#{key} is missing match"
      assert rule["policy"].present?, "#{key} is missing policy"
      assert rule["label"].present?, "#{key} is missing label"
      assert rule["severity"].present?, "#{key} is missing severity"
      assert rule["category"].present?, "#{key} is missing category"
    end
  end

  test "apify legacy keywords are covered by exported yaml rules" do
    rules = Distillator::WringerRules.all.map(&:last)
    body_terms = rules.flat_map { |rule| Array(rule.dig("match", "body_contains")) }
    body_text_terms = rules.flat_map { |rule| Array(rule.dig("match", "body_text_contains")) }
    http_codes = rules.flat_map { |rule| Array(rule.dig("match", "http_code")) }.map(&:to_i)

    %w[Reservatech Queue-it captcha Forbidden Waiting\ room POST\ call].each do |term|
      assert (body_terms.include?(term) || body_text_terms.include?(term)), "#{term.inspect} should be covered by a rule"
    end
    assert_includes body_terms, "Salle d'attente"
    assert_includes body_text_terms, "Une erreur est survenue"
    assert_includes body_text_terms, "An error occurred"
    assert_includes http_codes, 403
    assert_includes http_codes, 500
  end

  test "generic error text rule uses body text phrases instead of a broad html substring" do
    generic = Distillator::WringerRules.find("generic_error_text").last

    assert_equal [], Array(generic.dig("match", "body_contains"))
    assert_includes Array(generic.dig("match", "body_text_contains")), "Une erreur est survenue"
    assert_includes Array(generic.dig("match", "body_text_contains")), "An error occurred"
  end
end
