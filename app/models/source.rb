class Source < ApplicationRecord
  belongs_to :property
  belongs_to :website
  has_many :statements, dependent: :destroy

  def json_post?
    algorithm_value.to_s.split(";").any? { |step| step.strip.start_with?("post_url=") }
  end
end
