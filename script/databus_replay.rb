# Rails console: load Rails.root.join("script/databus_replay.rb")
# report = Distillator::DatabusReplay.call(sites: ["co-motion-ca"], per_site: 1)
# puts JSON.pretty_generate(report)
require Rails.root.join("app/services/distillator/databus_replay")
