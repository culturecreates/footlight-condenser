require "test_helper"
require "ostruct"

# VCR-backed scrape coverage lives here so StatementsHelperTest remains unit-fast.
# These tests may exercise recorded HTTP/VCR behavior and are intentionally not part
# of the fast unit preflight.
class StatementsHelperScrapeIntegrationTest < ActionView::TestCase
  include StatementsHelper

  setup do
    @distillator_config = Rails.application.config.x.distillator
    @old_compatibility_base_url = @distillator_config.compatibility_base_url
    @old_legacy_wringer_base_url = @distillator_config.legacy_wringer_base_url
    @old_allow_localhost = @distillator_config.allow_localhost_compatibility

    @distillator_config.compatibility_base_url = "http://localhost:3000"
    @distillator_config.legacy_wringer_base_url = "http://localhost:3009"
    @distillator_config.allow_localhost_compatibility = false
  end

  teardown do
    @distillator_config.compatibility_base_url = @old_compatibility_base_url
    @distillator_config.legacy_wringer_base_url = @old_legacy_wringer_base_url
    @distillator_config.allow_localhost_compatibility = @old_allow_localhost
  end

  test "process_algorithm sparql" do
    expected = ["DOMINIC PAQUET • LAISSE-MOI PARTIR"]

    VCR.use_cassette("StatementsHelper:complexeculturelfelixleclerc") do
      assert_equal expected, process_algorithm(
        algorithm: "sparql={?s a schema:Event. ?s schema:name ?answer}",
        url: "https://www.complexeculturelfelixleclerc.com/event-details/dominic-paquet-laisse-moi-partir"
      )
    end
  end

  test "process_algorithm sparql with nested image" do
    expected = ["https://static.wixstatic.com/media/28fd07_aa7b850feecb4363878aa75c34296221~mv2.jpg/v1/fill/w_537,h_534,al_c,q_80/28fd07_aa7b850feecb4363878aa75c34296221~mv2.jpg"]

    VCR.use_cassette("StatementsHelper:complexeculturelfelixleclerc") do
      assert_equal expected, process_algorithm(
        algorithm: "sparql={?s a schema:Event. ?s schema:image/schema:url ?answer}",
        url: "https://www.complexeculturelfelixleclerc.com/event-details/dominic-paquet-laisse-moi-partir"
      )
    end
  end

  test "process_algorithm sparql with filter" do
    expected = ["https://static.wixstatic.com/media/28fd07_aa7b850feecb4363878aa75c34296221~mv2.jpg/v1/fill/w_537,h_534,al_c,q_80/28fd07_aa7b850feecb4363878aa75c34296221~mv2.jpg"]

    VCR.use_cassette("StatementsHelper:complexeculturelfelixleclerc") do
      assert_equal expected, process_algorithm(
        algorithm: "sparql={?s a schema:Event. ?s schema:image/schema:url ?answer . FILTER isURI(?answer) }",
        url: "https://www.complexeculturelfelixleclerc.com/event-details/dominic-paquet-laisse-moi-partir"
      )
    end
  end

  test "process_algorithm xpath" do
    expected = ["Culture Creates | Digital knowledge management for the arts"]

    VCR.use_cassette("StatementsHelper:culturecreates.com") do
      assert_equal expected, process_algorithm(algorithm: "xpath=//title", url: "http://culturecreates.com")
    end
  end

  test "process_algorithm if_xpath continue" do
    expected = ["Arts metadata compatible with an AI-powered world"]

    VCR.use_cassette("StatementsHelper:culturecreates.com") do
      assert_equal expected, process_algorithm(algorithm: "if_xpath=//title;xpath=(//h1)[1]", url: "http://culturecreates.com")
    end
  end

  test "process_algorithm if_xpath break" do
    VCR.use_cassette("StatementsHelper:culturecreates.com") do
      assert_equal [], process_algorithm(algorithm: "if_xpath=//nothing;xpath=(//h1)[1]", url: "http://culturecreates.com")
    end
  end

  test "process_algorithm unless_xpath break" do
    VCR.use_cassette("StatementsHelper:culturecreates.com") do
      assert_equal [], process_algorithm(algorithm: "unless_xpath=//title;xpath=(//h1)[1]", url: "http://culturecreates.com")
    end
  end

  test "process_algorithm unless_xpath continue" do
    expected = ["Arts metadata compatible with an AI-powered world"]

    VCR.use_cassette("StatementsHelper:culturecreates.com") do
      assert_equal expected, process_algorithm(algorithm: "unless_xpath=//nothing;xpath=(//h1)[1]", url: "http://culturecreates.com")
    end
  end

  test "process_algorithm url and xpath" do
    VCR.use_cassette("StatementsHelper:process_algorithm url and xpath") do
      assert_equal ["ArtsdataApi"], process_algorithm(
        algorithm: "url='http://api.artsdata'+'.ca';xpath=//title",
        url: "http://culturecreates.com"
      )
    end
  end

  test "process_algorithm double xpath" do
    VCR.use_cassette("StatementsHelper:culturecreates.com") do
      assert_equal ["IE=edge"], process_algorithm(
        algorithm: "xpath=//title;xpath=(//meta/@content)[1]",
        url: "http://culturecreates.com"
      )
    end
  end

  test "process_algorithm url and json and ruby" do
    algorithm = "url=$url + '.json';json=$json.dig('date','end');ruby=$array[0] ? [$json.dig('date','start')] : $array;time_zone='Eastern Time (US & Canada)'"

    VCR.use_cassette("StatementsHelper: process_algorithm url and json and ruby") do
      assert_equal ["time_zone: 'Eastern Time (US & Canada)'"], process_algorithm(
        algorithm: algorithm,
        url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe"
      )
    end
  end

  test "should scrape title from html" do
    source = sources(:one)
    source.algorithm_value = "xpath=//title"

    VCR.use_cassette("StatementsHelper: should scrape title from html") do
      assert_equal ["Culture Creates | Digital knowledge management for the arts"], scrape(source, "http://culturecreates.com")
    end
  end

  test "should scrape 2 items from html" do
    source = OpenStruct.new(algorithm_value: 'xpath=//title;xpath=//meta[@property="og:title"]/@content')

    VCR.use_cassette("StatementsHelper: should scrape 2 items from html") do
      assert_equal ["Culture Creates Inc"], scrape(source, "http://culturecreates.com")
    end
  end

  test "should concatenate 2 items from html" do
    source = OpenStruct.new(algorithm_value: 'xpath=//title | //meta[@property="og:title"]/@content;ruby=$array[0]+ " | " + $array[1]')

    VCR.use_cassette("StatementsHelper: should concatenate 2 items from html") do
      actual_output = scrape(source, "http://culturecreates.com")
      expected_variants = [
        "Culture Creates | Digital knowledge management for the arts | Culture Creates Inc",
        "Culture Creates Inc | Culture Creates | Digital knowledge management for the arts"
      ]
      assert_includes expected_variants, actual_output
    end
  end
end
