# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_page_query"

class NumberedPageQueryTest < Minitest::Test
  def test_chasse_galerie_preserves_page_size_and_category
    url = "https://www.chasse-galerie.ca/fr/calendrier?page=1&number_items=48&categ=concert"
    query = ResourceLists::NumberedPageQuery.new(start_url: url)
    assert_equal "https://www.chasse-galerie.ca/fr/calendrier?page=2&number_items=48&categ=concert", query.url_for(2)
    assert query.matches_page?(query.url_for(2), page: 2)
    refute query.matches_page?("https://www.chasse-galerie.ca/fr/calendrier?page=2", page: 2)
    refute query.matches_page?("https://www.chasse-galerie.ca/fr/calendrier?page=2&number_items=48&categ=all", page: 2)
  end

  def test_ccat_repeated_category_keys_are_preserved
    url = "https://ccat.qc.ca/vitrine/?pag=1&typeevenement%5B%5D=389&typeevenement%5B%5D=252&mrc=&du=2022-08-01"
    query = ResourceLists::NumberedPageQuery.new(start_url: url)
    assert_equal "pag", query.parameter
    assert query.matches_page?(query.url_for(5), page: 5)
    refute query.matches_page?(query.url_for(5).sub("252", "253"), page: 5)
    refute query.matches_page?(query.url_for(5).sub("&mrc=", ""), page: 5)
    reordered = "https://ccat.qc.ca/vitrine/?du=2022-08-01&typeevenement%5B%5D=252&pag=5&mrc=&typeevenement%5B%5D=389"
    assert query.matches_page?(reordered, page: 5)
  end

  def test_supports_other_numeric_parameters_and_zero_based_pagination
    %w[p pageNumber p_numb page pag].each do |name|
      query = ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/calendar?#{name}=0&category=A")
      assert_equal 0, query.first_page
      assert query.matches_page?(query.url_for(1), page: 1)
    end
  end

  def test_requires_explicit_parameter_if_ambiguous
    assert_raises(ArgumentError) do
      ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/?page=1&pag=1&cat=123")
    end
    query = ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/?page=1&pag=1&cat=123", parameter: "page")
    assert query.matches_page?(query.url_for(2), page: 2)
    refute query.matches_page?("https://example.org/?page=2&pag=2&cat=123", page: 2)
  end

  def test_rejects_unsafe_or_changed_urls
    assert_raises(ArgumentError) { ResourceLists::NumberedPageQuery.new(start_url: "http://example.org/?page=1") }
    assert_raises(ArgumentError) { ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/?page=abc") }
    assert_raises(ArgumentError) { ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/?page=1&page=2") }
    q = ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/calendar?page=1&category=A")
    refute q.matches_page?("https://evil.org/calendar?page=2&category=A", page: 2)
    refute q.matches_page?("https://example.org/other?page=2&category=A", page: 2)
    refute q.matches_page?("https://example.org/calendar?page=3&category=A", page: 2)
    refute q.matches_page?("https://example.org/calendar?page=2&category=A&extra=1", page: 2)
  end
  def test_le_point_de_vente_preserves_encoded_json_categories_and_selected_radius
    url = "https://lepointdevente.com/?q=&type=physical&locality=2234&radius=30&categories=%7B%221%22%3A0%7D&lang=fr&page=2"
    query = ResourceLists::NumberedPageQuery.new(start_url: url)
    assert_equal 2, query.first_page
    [1, 2, 3].each { |page| assert query.matches_page?(query.url_for(page), page: page) }
    params = URI.decode_www_form(URI.parse(query.url_for(3)).query).to_h
    assert_equal "30", params.fetch("radius")
    assert_equal '{"1":0}', params.fetch("categories")
  end

  def test_le_point_de_vente_never_merges_different_filter_chains
    base = "https://lepointdevente.com/?q=&type=physical&locality=2234&radius=30&categories=%7B%221%22%3A0%7D&lang=fr&page=2"
    query = ResourceLists::NumberedPageQuery.new(start_url: base)
    refute query.matches_page?(base.sub("radius=30", "radius=31"), page: 2)
    refute query.matches_page?(base.sub("%221%22", "%2211%22"), page: 2)
    refute query.matches_page?(base.sub("locality=2234", "locality=2235"), page: 2)
    refute query.matches_page?(base.sub("lang=fr", "lang=en"), page: 2)
    refute query.matches_page?(base.sub("q=&", ""), page: 2)
  end

  def test_le_point_de_vente_ambiguous_p_key_requires_page_parameter
    base = "https://lepointdevente.com/?q=&type=physical&locality=2234&radius=30&categories=%7B%221%22%3A0%7D&lang=fr&p=156&page=2"
    assert_raises(ArgumentError) { ResourceLists::NumberedPageQuery.new(start_url: base) }
    query = ResourceLists::NumberedPageQuery.new(start_url: base, parameter: "page")
    assert query.matches_page?(query.url_for(3), page: 3)
    refute query.matches_page?(query.url_for(3).sub("p=156", "p=157"), page: 3)
  end

end
