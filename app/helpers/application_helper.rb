module ApplicationHelper

  def list_of_websites
    @list_of_websites ||= Website.all.order(:name)
  end

end
