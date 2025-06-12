module DatabusHelper
  def make_databus_artifact(seedurl)
    seedurl
  end

  def make_databus_version
    Time.zone.today.iso8601
  end

  def make_databus_file(seedurl)
    "#{seedurl}.json"
  end

  def make_databus_group
    "footlight"
  end

  def make_databus_download_url(seedurl, version)
    # https://data.culturecreates.com/databus/culture-creates/footlight/crowstheatre-com/2021-05-13/crowstheatre-com.json
    "https://data.culturecreates.com/databus/culture-creates/#{make_databus_group}/#{make_databus_artifact(seedurl)}/#{version}/#{make_databus_file(seedurl)}"
  end
end
