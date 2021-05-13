module WebsitesHelper
  def display_time(t)
    return unless t

    t.strftime('%H:%M %Z')
  end
end
