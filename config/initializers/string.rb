# Additional methods for String
class String
  # This handles the messy conversion of the database string if serialized JSON
  def make_into_array
    if self[0] == '['
      begin
        JSON.parse(self)
      rescue JSON::ParserError
        Array(self)
      end
    else
      Array(self)
    end
  end
end
