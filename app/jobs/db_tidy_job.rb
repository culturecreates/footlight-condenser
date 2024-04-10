# Clean up database records that are old to make space.
class DbTidyJob < ApplicationJob
  queue_as :default
  def perform()
    Message.where("updated_at < ?", Date.today - 1.months).delete_all  # delete_all does not delete dependancies
    # Find websites with lots of Event pages, and delete old webpages based on archive_date
    websites = Webpage.includes(:rdfs_class).where( rdfs_classes: {name: "Event"}).group(:website).count.select { |website,count| count > 100 }.map { |website,count| website}
    Webpage.includes(:rdfs_class).where(website: websites).where("archive_date < ?", Date.today - 1.months).where(rdfs_classes: {name: "Event"}).destroy_all # destroy_all will delete all statements per webpage. Destroys the records by instantiating each record and calling its #destroy method. Each object's callbacks are executed (including :dependent association options).
  end
end