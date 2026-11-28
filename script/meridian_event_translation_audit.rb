# frozen_string_literal: true

# Four specific Meridian event pages: find *explicit* EN/FR translation
# relationships before any new RDF IDs are minted. No database reads/writes,
# refresh jobs, cache updates or imports. --live does ordinary HTTP GET only,
# never renders JS or attempts to evade website access controls.
require "digest"
require "json"
require "net/http"
require "optparse"
require "uri"

module MeridianEventTranslationAudit
  ROOT = "https://meridiancentrepointe.com"
  PAIRS = {
    "solitary_man" => {
      "en" => "#{ROOT}/en/solitary-man-neil-diamond-postponed",
      "fr" => "#{ROOT}/fr/solitary-man-neil-diamond-REPORTE"
    },
    "scaramouche" => {
      "en" => "#{ROOT}/en/scaramouche-queen-tribute-postponed",
      "fr" => "#{ROOT}/fr/scaramouche-hommage-queen-REPORTE"
    }
  }.freeze

  def self.fetch_page(url)
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 25) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "Footlight-Meridian-QA/1.0 (read-only translation metadata audit)"
      request["Accept"] = "text/html"
      request["Accept-Encoding"] = "identity"
      http.request(request)
    end
    raise "HTTP #{response.code} (not usable)" unless response.code.to_i == 200
    raise "Unexpected content type" unless response["content-type"].to_s.downcase.include?("html")
    body = response.body.to_s
    raise "Empty or oversized HTML" unless body.bytesize.between?(1, ResourceLists::MeridianEventTranslationEvidence::MAX_BYTES)
    body
  end

  def self.run(live:, snapshots:, output:)
    raise "Refusing production" if Rails.env.production?
    raise "Refusing overwrite #{output}" if output && File.exist?(output)
    raise "Use --live or supply all four --html snapshots" unless live || snapshots.size == 4
    raise "Cannot mix --live and --html" if live && snapshots.any?

    result = { generated_at: Time.current.utc.iso8601, read_only: true, input_mode: live ? "independent_live_http" : "operator_html",
      pairs: {}, fully_verified_pairs: 0, new_rdf_identities: 0,
      note: "Observed reciprocal hreflang can support a translation pair but does not establish an authoritative calendar inventory." }
    PAIRS.each do |name, urls|
      html = {}
      errors = {}
      urls.each do |language, url|
        begin
          html[language] = if live
            fetch_page(url)
          else
            path = snapshots.fetch([name, language])
            raise "Missing file: #{path}" unless File.file?(path)
            File.binread(path)
          end
        rescue StandardError => error
          errors[language] = "#{error.class}: #{error.message}"
        end
      end
      assessment = if errors.empty?
        ResourceLists::MeridianEventTranslationEvidence.call(urls: urls, documents: html)
      else
        { status: "blocked", errors: errors, reciprocal_head_alternates: false, action: "none", rdf_minted: 0 }
      end
      result[:pairs][name] = assessment
      result[:fully_verified_pairs] += 1 if assessment[:status] == "verified_reciprocal_translation"
      puts "#{name}: #{assessment[:status]} shared_key=#{assessment[:verified_shared_key] || "unverified"} node_conflict=#{assessment[:node_id_conflict] || false}"
      if assessment[:pages]
        assessment[:pages].each do |language, page|
          puts "  #{language.upcase} #{page[:state]} title=#{page[:title].inspect} alternates=#{page[:head_alternates].inspect} shortlinks=#{page[:drupal_shortlinks].inspect} drupal_node_id=#{page[:drupal_node_id] || "unknown"}"
          Array(page[:errors]).each { |error| puts "    #{error}" }
        end
      else
        errors.each { |lang, error| puts "  #{lang.upcase} #{error}" }
      end
    end
    puts "Verified reciprocal translation pairs: #{result[:fully_verified_pairs]}/2. No RDF minting or changes."
    if output
      File.write(output, JSON.pretty_generate(result) + "\n")
      puts "Saved #{output}"
    end
    result
  end
end

live = false
snapshots = {}
output = nil
OptionParser.new do |opts|
  opts.on("--live", "Fetch all four public pages as read-only HTML") { live = true }
  opts.on("--html PAIR:LANG:PATH", "Use a locally saved event document") do |spec|
    pair, language, path = spec.split(":", 3)
    abort "Invalid --html: #{spec}" unless MeridianEventTranslationAudit::PAIRS.key?(pair) &&
      %w[en fr].include?(language) && path.present? && !snapshots.key?([pair, language])
    snapshots[[pair, language]] = path
  end
  opts.on("--json PATH") { |value| output = value }
end.parse!(ARGV)
abort "Unexpected arguments" unless ARGV.empty?
MeridianEventTranslationAudit.run(live: live, snapshots: snapshots, output: output)
