module Distillator
  module Cohorts
    class LavitrinePipeline
      KEY = "lavitrine_pipeline".freeze
      LABEL = "La Vitrine pipeline".freeze
      QUERY_URL = "https://raw.githubusercontent.com/artsdata-stewards/artsdata-actions/main/queries/lavitrine_pipeline.sparql".freeze

      FEED_NAMES = %w[
        gatineau-cloud
        ccat-qc-ca
        theatredumarais-com
        ptitbonheur-org
        centredesartsbc-com
        culturegaspesie-org
        diffusion-saguenay-ca
        theatregillesvigneault-com
        quoivivrerimouski-ca
        hector-charland-com
        diffusionmordicus-tuxedobillet-com
        theatrepatriote-com
        amphitheatrecogeco-com
        spectaclesjoliette-com
        stprime-tuxedobillet-com
        petittheatre-org
        lecarre150-com
        centredecreationdiffusiondegaspe-com
        placedesarts-com
        maisondelaculture-ca
        chasse-galerie-ca
        minotaure-ca
        derived-grandtheatre-qc-ca
        signe-laval
        theatregranada-com
        tout-culture
        culture-mauricie
      ].freeze

      def self.key
        KEY
      end

      def self.label
        config.fetch(:label, LABEL)
      end

      def self.query_url
        config.fetch(:source_url, QUERY_URL)
      end

      def self.feed_names
        Array(config[:feed_names]).presence || FEED_NAMES
      end

      def self.match_fields
        Array(config[:match_fields]).presence || %w[seedurl name code]
      end

      def self.config
        Distillator::Cohorts::Registry.fetch(KEY) || {
          key: KEY,
          label: LABEL,
          source_url: QUERY_URL,
          match_fields: %w[seedurl name code],
          feed_names: FEED_NAMES
        }
      end
    end
  end
end
