require "test_helper"

class ForeignKeyOrderedFixturesTest < ActiveSupport::TestCase
  test "fixture references are valid without disabling PostgreSQL foreign keys" do
    assert_equal rdfs_classes(:one).id, properties(:one).rdfs_class_id
    assert_equal rdfs_classes(:place).id, properties(:two).rdfs_class_id
    assert_equal properties(:one).id, sources(:one).property_id
    assert_equal websites(:one).id, sources(:one).website_id
    assert_equal rdfs_classes(:one).id, webpages(:one).rdfs_class_id
    assert_equal websites(:one).id, webpages(:one).website_id
  end

  test "fixture loading order follows FK dependencies, unlike Rails alphabetical sort" do
    tables = %w[properties statements sources webpages websites rdfs_classes jsonld_outputs]
    order = ActiveRecord::Base.connection.send(:fixture_dependency_order, tables)
    assert_operator order.index("rdfs_classes"), :<, order.index("properties")
    assert_operator order.index("properties"), :<, order.index("sources")
    assert_operator order.index("sources"), :<, order.index("statements")
    assert_operator order.index("websites"), :<, order.index("webpages")
    assert_operator order.index("jsonld_outputs"), :<, order.index("webpages")
  end
end
