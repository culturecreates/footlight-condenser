require 'test_helper'

class ExportGraphToDatabusTest < ActiveSupport::TestCase

  test "check schedule" do
    ExportGraphToDatabus.check_schedule('http://localhost:3000')
  end

end