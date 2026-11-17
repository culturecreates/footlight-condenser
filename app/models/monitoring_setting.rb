class MonitoringSetting < ApplicationRecord
  before_validation { self.mailbox = mailbox.to_s.strip.presence }
  validates :mailbox, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true

  def self.current
    find_by(id: 1) || create_or_find_by!(id: 1)
  end
end
