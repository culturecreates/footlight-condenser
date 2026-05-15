require "test_helper"

class HarmonizedUiInventoryTest < ActionDispatch::IntegrationTest
  InventoryTarget = Struct.new(
    :label,
    :helper,
    :sample_path,
    :controller,
    :action,
    :current_view,
    :master_view,
    keyword_init: true
  )

  CURRENT_ROOT = Rails.root
  MASTER_ROOT = Rails.root.join("..", "master", "footlight-condenser")

  INDEX_TARGETS = [
    InventoryTarget.new(
      label: "distillator cache index",
      helper: :distillator_cache_index,
      sample_path: "/distillator/cache",
      controller: "distillator/cache",
      action: "index",
      current_view: "app/views/distillator/cache/index.html.erb",
      master_view: nil
    ),
    InventoryTarget.new(
      label: "condenser cache alias",
      helper: :condenser_cache_index,
      sample_path: "/condenser/cache",
      controller: "distillator/cache",
      action: "index",
      current_view: "app/views/distillator/cache/index.html.erb",
      master_view: nil
    ),
    InventoryTarget.new(
      label: "webpages index",
      helper: :webpages,
      sample_path: "/webpages",
      controller: "webpages",
      action: "index",
      current_view: "app/views/webpages/index.html.erb",
      master_view: "app/views/webpages/index.html.erb"
    ),
    InventoryTarget.new(
      label: "sources index",
      helper: :sources,
      sample_path: "/sources",
      controller: "sources",
      action: "index",
      current_view: "app/views/sources/index.html.erb",
      master_view: "app/views/sources/index.html.erb"
    ),
    InventoryTarget.new(
      label: "website resources index",
      helper: :website_all_resources,
      sample_path: "/websites/example-seed/resources",
      controller: "resources",
      action: "index",
      current_view: nil,
      master_view: nil
    ),
    InventoryTarget.new(
      label: "statements index",
      helper: :statements,
      sample_path: "/statements",
      controller: "statements",
      action: "index",
      current_view: "app/views/statements/index.html.erb",
      master_view: "app/views/statements/index.html.erb"
    ),
    InventoryTarget.new(
      label: "properties index",
      helper: :properties,
      sample_path: "/properties",
      controller: "properties",
      action: "index",
      current_view: "app/views/properties/index.html.erb",
      master_view: "app/views/properties/index.html.erb"
    ),
    InventoryTarget.new(
      label: "rdfs classes index",
      helper: :rdfs_classes,
      sample_path: "/rdfs_classes",
      controller: "rdfs_classes",
      action: "index",
      current_view: "app/views/rdfs_classes/index.html.erb",
      master_view: "app/views/rdfs_classes/index.html.erb"
    ),
    InventoryTarget.new(
      label: "website events index",
      helper: :website_events,
      sample_path: "/websites/example-seed/events",
      controller: "events",
      action: "index",
      current_view: "app/views/events/index.html.erb",
      master_view: "app/views/events/index.html.erb"
    ),
    InventoryTarget.new(
      label: "website events by property index",
      helper: :website_events_by_property,
      sample_path: "/websites/example-seed/events_by_property",
      controller: "events",
      action: "index_by_property",
      current_view: nil,
      master_view: nil
    ),
    InventoryTarget.new(
      label: "places index",
      helper: :places,
      sample_path: "/places",
      controller: "places",
      action: "index",
      current_view: "app/views/places/index.html.erb",
      master_view: "app/views/places/index.html.erb"
    ),
    InventoryTarget.new(
      label: "reports source index",
      helper: :source_reports,
      sample_path: "/reports/source",
      controller: "reports",
      action: "source",
      current_view: "app/views/reports/source.html.erb",
      master_view: "app/views/reports/source.html.erb"
    )
  ].freeze

  CARD_TARGETS = [
    InventoryTarget.new(
      label: "distillator cache show",
      helper: :distillator_cache,
      sample_path: "/distillator/cache/123",
      controller: "distillator/cache",
      action: "show",
      current_view: "app/views/distillator/cache/show.html.erb",
      master_view: nil
    ),
    InventoryTarget.new(
      label: "webpage show",
      helper: :webpage,
      sample_path: "/webpages/123",
      controller: "webpages",
      action: "show",
      current_view: "app/views/webpages/show.html.erb",
      master_view: "app/views/webpages/show.html.erb"
    ),
    InventoryTarget.new(
      label: "source show",
      helper: :source,
      sample_path: "/sources/123",
      controller: "sources",
      action: "show",
      current_view: "app/views/sources/show.html.erb",
      master_view: "app/views/sources/show.html.erb"
    ),
    InventoryTarget.new(
      label: "resource show",
      helper: :show_resources,
      sample_path: "/resources/sample-rdf-uri",
      controller: "resources",
      action: "show",
      current_view: "app/views/resources/show.html.erb",
      master_view: "app/views/resources/show.html.erb"
    ),
    InventoryTarget.new(
      label: "statement show",
      helper: :statement,
      sample_path: "/statements/123",
      controller: "statements",
      action: "show",
      current_view: "app/views/statements/show.html.erb",
      master_view: "app/views/statements/show.html.erb"
    ),
    InventoryTarget.new(
      label: "property show",
      helper: :property,
      sample_path: "/properties/123",
      controller: "properties",
      action: "show",
      current_view: "app/views/properties/show.html.erb",
      master_view: "app/views/properties/show.html.erb"
    ),
    InventoryTarget.new(
      label: "rdfs class show",
      helper: :rdfs_class,
      sample_path: "/rdfs_classes/123",
      controller: "rdfs_classes",
      action: "show",
      current_view: "app/views/rdfs_classes/show.html.erb",
      master_view: "app/views/rdfs_classes/show.html.erb"
    )
  ].freeze

  CURRENT_BRANCH_ONLY_FILES = [
    "app/controllers/distillator/cache_controller.rb",
    "app/views/distillator/cache/index.html.erb",
    "app/views/distillator/cache/show.html.erb",
    "test/controllers/distillator/cache_controller_test.rb"
  ].freeze

  SHARED_CONTROLLER_TESTS = [
    "test/controllers/webpages_controller_test.rb",
    "test/controllers/sources_controller_test.rb",
    "test/controllers/resources_controller_test.rb",
    "test/controllers/statements_controller_test.rb",
    "test/controllers/properties_controller_test.rb",
    "test/controllers/rdfs_classes_controller_test.rb",
    "test/controllers/events_controller_test.rb",
    "test/controllers/places_controller_test.rb",
    "test/controllers/reports_controller_test.rb"
  ].freeze

  test "inventory confirms condenser and distillator index routes" do
    INDEX_TARGETS.each do |target|
      assert_named_get_route(target)
      assert_view_presence(target.current_view, root: CURRENT_ROOT, label: target.label, expected: !target.current_view.nil?)
      assert_view_presence(target.master_view, root: MASTER_ROOT, label: target.label, expected: !target.master_view.nil?)
    end
  end

  test "inventory confirms condenser and distillator card targets" do
    CARD_TARGETS.each do |target|
      assert_named_get_route(target)
      assert_view_presence(target.current_view, root: CURRENT_ROOT, label: target.label, expected: !target.current_view.nil?)
      assert_view_presence(target.master_view, root: MASTER_ROOT, label: target.label, expected: !target.master_view.nil?)
    end
  end

  test "inventory shows distillator cache is current branch only and excludes wringer console files" do
    CURRENT_BRANCH_ONLY_FILES.each do |relative_path|
      assert_file_exists CURRENT_ROOT.join(relative_path), "#{relative_path} should exist in the current branch"
      assert_file_missing MASTER_ROOT.join(relative_path), "#{relative_path} should not exist in the master reference tree"
    end

    SHARED_CONTROLLER_TESTS.each do |relative_path|
      assert_file_exists CURRENT_ROOT.join(relative_path), "#{relative_path} should exist in the current branch"
      assert_file_exists MASTER_ROOT.join(relative_path), "#{relative_path} should exist in the master reference tree"
    end

    inventory_strings.each do |value|
      assert_no_match(/footlight-wringer/i, value)
      assert_no_match(/footlight-console/i, value)
      assert_no_match(%r{/(?:wringer|console)(?:/|_|$)}i, value)
    end
  end

  private

  def assert_named_get_route(target)
    recognized = Rails.application.routes.recognize_path(target.sample_path, method: :get)
    assert_equal target.controller, recognized[:controller], "#{target.label} controller mismatch"
    assert_equal target.action, recognized[:action], "#{target.label} action mismatch"
  end

  def assert_view_presence(relative_path, root:, label:, expected:)
    if expected
      assert_file_exists root.join(relative_path), "#{label} should render #{relative_path}"
    else
      if relative_path
        assert_file_missing root.join(relative_path), "#{label} should not have an HTML view in #{root}"
      else
        assert_nil relative_path, "#{label} should not declare an HTML view path"
      end
    end
  end

  def assert_file_exists(path, message)
    assert path.exist?, message
  end

  def assert_file_missing(path, message)
    assert_not path.exist?, message
  end

  def inventory_strings
    (INDEX_TARGETS + CARD_TARGETS).flat_map do |target|
      [target.label, target.helper.to_s, target.sample_path, target.controller, target.action, target.current_view.to_s, target.master_view.to_s]
    end + CURRENT_BRANCH_ONLY_FILES + SHARED_CONTROLLER_TESTS
  end
end
