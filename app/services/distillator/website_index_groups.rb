module Distillator
  class WebsiteIndexGroups
    LABELS = { scheduled: "Scheduled sites", unscheduled: "Unscheduled", entities: "Places / Artists / People",
      templates: "Templates", tests: "Test sites" }.freeze
    TEMPLATE_SEEDS = %w[1-event 2-en-event 2-fr-event 3-person-place-org 4-en-person-place-org 4-fr-person-place-org footlight-manual-fr].freeze
    ENTITY_SEEDS = %w[signelaval-com signelaval-com-place spec-qc-ca-people nowplayingtoronto-com-places].freeze

    def self.call(websites)
      Array(websites).each_with_object(LABELS.keys.index_with { [] }) do |website, groups|
        groups.fetch(category(website)) << website
      end
    end

    def self.category(website)
      seed = website.seedurl.to_s.downcase
      name = website.name.to_s
      return :templates if TEMPLATE_SEEDS.include?(seed) || name.match?(/\btemplate\b/i)
      return :tests if "#{name} #{seed.tr('_', '-')}".match?(/\btest(?:ing|website)?\b/i)
      return :entities if ENTITY_SEEDS.include?(seed) || seed.match?(/[-_](?:places?|artists?|people|persons?)\z/i) ||
        name.match?(/(?:\A|\s)(?:places|artists|people|artistes|personnes)\z/i)

      website.schedule_every_days.to_i.positive? ? :scheduled : :unscheduled
    end
  end
end
