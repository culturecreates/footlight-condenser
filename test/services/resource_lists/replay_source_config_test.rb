# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../app/services/resource_lists/replay_source_config"

class ReplaySourceConfigTest < Minitest::Test
  def config
    {"source_id" => 9102, "website_id" => 71, "website_seedurl" => "tourismeshawinigan-com",
     "property_label" => "Webpage URL List", "selected" => true, "render_js" => false,
     "algorithm_value" => "xpath=//a/@href\r\n;ruby=$array.select{|e| e =~ /occurrence_date/}"}
  end

  def test_preserves_original_multiline_dsl
    value = ResourceLists::ReplaySourceConfig.new(config)
    assert_equal config.fetch("algorithm_value"), value.algorithm_value
    assert_equal 9102, value.source_id
    assert_equal false, value.render_js
  end

  def test_accepts_selected_uri_source
    value = ResourceLists::ReplaySourceConfig.new(config.merge("property_label" => "URI List", "source_id" => 9098))
    assert_equal "URI List", value.property_label
  end

  def test_loads_json_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "source.json")
      File.binwrite(path, JSON.generate(config))
      assert_equal config.fetch("algorithm_value"), ResourceLists::ReplaySourceConfig.from_file(path).algorithm_value
    end
  end

  def test_rejects_unselected_source
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("selected" => false)) }
  end

  def test_rejects_irrelevant_property
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("property_label" => "Description")) }
  end

  def test_rejects_empty_algorithm
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("algorithm_value" => "  ")) }
  end

  def test_rejects_missing_or_invalid_identity
    assert_raises(KeyError) { ResourceLists::ReplaySourceConfig.new(config.reject { |k, _| k == "website_id" }) }
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("source_id" => "9102")) }
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("source_id" => -1)) }
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("website_seedurl" => "")) }
  end

  def test_rejects_invalid_render_js
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new(config.merge("render_js" => "false")) }
  end

  def test_requires_object
    assert_raises(ArgumentError) { ResourceLists::ReplaySourceConfig.new([]) }
  end
end
