# frozen_string_literal: true

# Rails 8 sorts fixture table names alphabetically, then uses DISABLE TRIGGER ALL
# to permit child-first DELETE/INSERT statements. PostgreSQL 17 requires a
# superuser for that operation. Local test roles should not require superuser.
#
# In test only, order fixture table deletes child-first and inserts parent-first
# using the *actual database foreign keys*. This keeps constraints enabled.
# Fail clearly on cross-table cycles, rather than bypassing FK validation.
module TestSupport
  module ForeignKeyOrderedFixtures
    def insert_fixtures_set(fixture_set, tables_to_delete = [])
      return super unless Rails.env.test?

      names = (tables_to_delete + fixture_set.keys).map(&:to_s).uniq
      order = fixture_dependency_order(names)
      rows = fixture_set.transform_keys(&:to_s)
      deletions = tables_to_delete.map(&:to_s)

      sql = order.reverse.filter_map do |table|
        "DELETE FROM #{quote_table_name(table)}" if deletions.include?(table)
      end
      sql.concat(build_fixture_statements(order.each_with_object({}) do |table, result|
        result[table] = rows.fetch(table) if rows.key?(table)
      end))

      transaction(requires_new: true) { execute_batch(sql, "Foreign-key ordered fixtures load") }
    end

    private

    def fixture_dependency_order(tables)
      deps = tables.to_h do |table|
        parents = foreign_keys(table).map { |fk| fk.to_table.to_s.split(".").last }
        [table, parents.select { |parent| parent != table && tables.include?(parent) }.uniq]
      end

      ordered = []
      until deps.empty?
        ready = deps.keys.find { |table| (deps[table] - ordered).empty? }
        raise "Cyclic fixture table dependencies: #{deps.keys.join(', ')}" unless ready

        ordered << ready
        deps.delete(ready)
      end
      ordered
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(TestSupport::ForeignKeyOrderedFixtures)
