module Distillator
  class CapabilityMap
    include Rails.application.routes.url_helpers

    Section = Struct.new(:title, :features, keyword_init: true)
    Feature = Struct.new(
      :name,
      :purpose,
      :implementation_status,
      :wringer_dependency_status,
      :transition_relevance,
      :evidence_source,
      :operator_label,
      :operator_path,
      :badges,
      keyword_init: true
    )
    LadderStep = Struct.new(:name, :purpose, :operator_surface, :badges, keyword_init: true)
    Result = Struct.new(:sections, :activation_readiness_ladder, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def call
      Result.new(
        sections: capability_sections,
        activation_readiness_ladder: activation_readiness_ladder
      )
    end

    private

    def capability_sections
      [
        Section.new(
          title: "Fetch & Cache",
          features: [
            feature(
              name: "Condenser cache index",
              purpose: "Inspect stored HTML, HTTP status, and cache-health signals without triggering refreshes.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Uses Wringer-compatible cache views for parity inspection, but the page itself reads Condenser cache rows only.",
              transition_relevance: "Primary operator surface for sampled-URL fetch evidence before activation.",
              evidence_source: "Distillator::CacheController#index + Distillator::CacheIndexQuery",
              operator_label: "Open Condenser cache",
              operator_path: distillator_cache_index_path,
              badges: ["Implemented", "Read-only", "Production-critical"]
            ),
            feature(
              name: "Cache compare",
              purpose: "Compare Condenser and Wringer HTML/cache payloads for the same URL.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Direct parity check against legacy Wringer cache or compatibility payloads.",
              transition_relevance: "Core fetch-parity gate for the transition report and manual review.",
              evidence_source: "Distillator::CacheCompare + /distillator/cache/compare",
              operator_label: "Compare Condenser vs Wringer",
              operator_path: condenser_cache_compare_path,
              badges: ["Implemented", "Read-only", "Transition-only"]
            ),
            feature(
              name: "Cache fetch command",
              purpose: "Run a direct, rendered, or POST fetch into the Condenser cache when operators need fresh evidence.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Condenser-only write path; parity comes from the resulting cache inspection.",
              transition_relevance: "Repair action when a representative URL is stale, missing, or unhealthy.",
              evidence_source: "Distillator::CacheFetchCommand + Distillator::FetchCacheStore",
              operator_label: "Cache operations",
              operator_path: distillator_cache_index_path,
              badges: ["Implemented", "Writes data", "Needs review"]
            )
          ]
        ),
        Section.new(
          title: "Statement Extraction",
          features: [
            feature(
              name: "Webpage statement refresh",
              purpose: "Refresh selected statements from webpage HTML using the current DSL/source configuration.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Reuses the same statement extraction stack that production statement refresh depends on.",
              transition_relevance: "Feeds the sampled statement parity checks before activation.",
              evidence_source: "StatementsController#refresh_webpage + Distillator::RefreshRunner",
              operator_label: "Open statements",
              operator_path: statements_path,
              badges: ["Implemented", "Writes data", "Production-critical"]
            ),
            feature(
              name: "Extracted statement parity",
              purpose: "Compare statements extracted from legacy Wringer HTML and Condenser HTML for one webpage.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Reads legacy Wringer HTML through cache compare without persisting statements or sources.",
              transition_relevance: "Primary read-only statement parity diagnostic for sampled URLs.",
              evidence_source: "Statements::ExtractedParityComparisonService + /statements/compare_extracted",
              operator_label: "Compare extracted statements",
              operator_path: compare_extracted_statements_path,
              badges: ["Implemented", "Read-only", "Transition-only"]
            )
          ]
        ),
        Section.new(
          title: "Sources / DSL",
          features: [
            feature(
              name: "Source inventory",
              purpose: "Review source templates by property, label, and DSL algorithm value at a glance.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Shared source templates remain the main parity surface between legacy and Condenser extraction.",
              transition_relevance: "Used to identify DSL drift before re-running sampled parity checks.",
              evidence_source: "SourcesController#index + Sources::IndexQuery",
              operator_label: "Open sources",
              operator_path: sources_path,
              badges: ["Implemented", "Read-only", "Production-critical"]
            ),
            feature(
              name: "Statement trace and DSL diagnostics",
              purpose: "Show per-statement execution traces, trace steps, and operator diagnosis for DSL failures.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Explains Condenser execution directly; legacy parity is inferred through the compared output.",
              transition_relevance: "Used when statement parity is unclear or when a sampled statement check fails.",
              evidence_source: "StatementsController#show + TracePresenter + Dsl::Tracing",
              operator_label: "Inspect statement traces",
              operator_path: statements_path,
              badges: ["Implemented", "Read-only", "Needs review"]
            )
          ]
        ),
        Section.new(
          title: "JSON-LD Export",
          features: [
            feature(
              name: "Export graph diff",
              purpose: "Compare current export output against a production-equivalent graph and surface RDF additions/removals.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Measures Condenser output against the legacy-equivalent export baseline.",
              transition_relevance: "Final parity gate before activation when fetch and statements look healthy.",
              evidence_source: "Distillator::GraphDiff + Distillator::TransitionCheckRunner",
              operator_label: "Open transition report",
              operator_path: distillator_shadow_report_path,
              badges: ["Implemented", "Read-only", "Production-critical"]
            ),
            feature(
              name: "Export normalization",
              purpose: "Normalize current and production-equivalent export payloads before graph comparison.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Keeps Wringer-era export comparisons stable while Condenser becomes primary.",
              transition_relevance: "Prevents false export drift during rollout review.",
              evidence_source: "Distillator::ExportNormalizer",
              operator_label: "Review export parity",
              operator_path: distillator_shadow_report_path,
              badges: ["Implemented", "Read-only"]
            )
          ]
        ),
        Section.new(
          title: "Transition / Rollout",
          features: [
            feature(
              name: "Transition report",
              purpose: "Summarize fetch, statements, export, readiness, and operator actions for shadow and active rollout.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Shows Wringer-backed and Condenser-backed production states side by side.",
              transition_relevance: "Primary operator entry point for activation and rollback decisions.",
              evidence_source: "Distillator::ShadowReport + Distillator::ShadowSiteDetail",
              operator_label: "Open transition report",
              operator_path: distillator_shadow_report_path,
              badges: ["Implemented", "Read-only", "Transition-only"]
            ),
            feature(
              name: "Review activation",
              purpose: "Activate after manual review with a recorded reason when parity differences are acceptable.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Explicit bridge from Wringer-backed review state into Condenser active rollout.",
              transition_relevance: "Operator override path after checklist review.",
              evidence_source: "Distillator::RolloutTransition + WebsitesController#activate_after_review",
              operator_label: "Review activation path",
              operator_path: distillator_shadow_report_path,
              badges: ["Implemented", "Writes data", "Needs review"]
            ),
            feature(
              name: "Rollback path",
              purpose: "Move a site back to legacy production if Condenser active rollout needs to be reversed.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Restores Wringer as the production backend and preserves Condenser evidence for inspection.",
              transition_relevance: "Safety valve after active rollout.",
              evidence_source: "Distillator::RolloutTransition + transition contract action surface",
              operator_label: "Rollback guidance",
              operator_path: distillator_shadow_report_path,
              badges: ["Implemented", "Writes data", "Production-critical"]
            )
          ]
        ),
        Section.new(
          title: "Diagnostics / Reports",
          features: [
            feature(
              name: "Representative URL matrix",
              purpose: "Show per-sampled-URL fetch, legacy lookup, compare, statement, and export outcomes in one table.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Includes legacy lookup and cache-compare results for each sampled URL.",
              transition_relevance: "Fastest way to isolate which sampled URL and layer failed.",
              evidence_source: "Distillator::ShadowSiteDetail#url_matrix",
              operator_label: "Review sampled URLs",
              operator_path: distillator_shadow_report_path,
              badges: ["Implemented", "Read-only", "Transition-only"]
            ),
            feature(
              name: "Capabilities map",
              purpose: "Document the current Condenser / Distillator operator surface without invoking any runtime actions.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Explains which surfaces are legacy-backed, parity-focused, or purely Distillator.",
              transition_relevance: "Orientation page for rollout, parity review, and operator onboarding.",
              evidence_source: "Distillator::CapabilityMap + /distillator/capabilities",
              operator_label: "Open system map",
              operator_path: distillator_capabilities_path,
              badges: ["Implemented", "Read-only"]
            )
          ]
        ),
        Section.new(
          title: "Operations / Safety",
          features: [
            feature(
              name: "Fetch guards and URL safety",
              purpose: "Apply safe-mode checks, URL policy checks, and fetch eligibility rules before operational actions run.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Protects Condenser operations while preserving legacy-compatible inspection paths.",
              transition_relevance: "Prevents unsafe refreshes and repair actions during rollout work.",
              evidence_source: "Distillator::FetchGuard + Distillator::UrlSafetyPolicy + Distillator::FetchEligibility",
              operator_label: "Review cache safety",
              operator_path: distillator_cache_index_path,
              badges: ["Implemented", "Production-critical", "Needs review"]
            ),
            feature(
              name: "Staging rollout repair",
              purpose: "Repair staging rollout modes that violate the expected legacy/shadow/active contract.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Keeps staging aligned with the same legacy-vs-Condenser serving assumptions used in production review.",
              transition_relevance: "Operational safety tool before transition checks and staged activation tests.",
              evidence_source: "Distillator::StagingRolloutRepair + OptionsController#repair_staging_rollout",
              operator_label: "Open options",
              operator_path: options_path,
              badges: ["Implemented", "Writes data", "Needs review"]
            )
          ]
        ),
        Section.new(
          title: "Legacy Wringer Compatibility",
          features: [
            feature(
              name: "Legacy Wringer compatibility endpoint",
              purpose: "Expose legacy-compatible website output for operators and compatibility checks.",
              implementation_status: "Legacy-backed",
              wringer_dependency_status: "Direct dependency on the Wringer compatibility surface.",
              transition_relevance: "Supports side-by-side investigation while legacy is still production for a site.",
              evidence_source: "WringerCompatibilityController + /websites/wring",
              operator_label: "Open Wringer compatibility",
              operator_path: wring_websites_path,
              badges: ["Legacy-backed", "Read-only", "Production-critical"]
            ),
            feature(
              name: "Active Wringer cache JSON",
              purpose: "Inspect Wringer-compatible cache JSON next to Condenser cache records.",
              implementation_status: "Implemented",
              wringer_dependency_status: "Mirrors legacy payload shape for direct comparison and debugging.",
              transition_relevance: "Useful when cache parity or representative URL evidence is disputed.",
              evidence_source: "Distillator::CacheController#wring_json_view",
              operator_label: "Open cache compatibility views",
              operator_path: distillator_cache_index_path,
              badges: ["Implemented", "Read-only", "Legacy-backed"]
            ),
            feature(
              name: "Legacy PhantomJS renderer",
              purpose: "Preserve the older JS-rendered fetch behavior for the remaining edge cases that still depend on it.",
              implementation_status: "Legacy-backed",
              wringer_dependency_status: "Direct compatibility seam with older rendered-fetch behavior.",
              transition_relevance: "Fallback context when native or newer rendered fetch modes do not yet match legacy behavior.",
              evidence_source: "Distillator::Renderers::LegacyPhantomjsRenderer",
              operator_label: "Review cache tooling",
              operator_path: distillator_cache_index_path,
              badges: ["Legacy-backed", "Deprecated", "Needs review"]
            )
          ]
        )
      ]
    end

    def activation_readiness_ladder
      [
        ladder_step(
          name: "Fetch parity",
          purpose: "Confirm Condenser fetches and stored cache output match the legacy comparison story for sampled URLs.",
          operator_surface: "Transition report + Cache compare",
          badges: ["Read-only", "Transition-only"]
        ),
        ladder_step(
          name: "Statement parity",
          purpose: "Check extracted statement parity on sampled URLs before trusting rollout readiness.",
          operator_surface: "Compare extracted statements + statement traces",
          badges: ["Read-only", "Transition-only"]
        ),
        ladder_step(
          name: "Export parity",
          purpose: "Compare current export output against the production-equivalent graph before activation.",
          operator_surface: "Transition report export diff",
          badges: ["Read-only", "Production-critical"]
        ),
        ladder_step(
          name: "Review activation",
          purpose: "Record a review reason and activate only when parity differences are acceptable and operator-checked.",
          operator_surface: "Activate after review",
          badges: ["Writes data", "Needs review"]
        ),
        ladder_step(
          name: "Active rollout",
          purpose: "Serve Condenser as production after the fetch, statement, and export gates are satisfied.",
          operator_surface: "Transition report decision surface",
          badges: ["Writes data", "Production-critical"]
        ),
        ladder_step(
          name: "Rollback path",
          purpose: "Return to legacy production if active rollout needs to be reversed safely.",
          operator_surface: "Transition report rollback guidance",
          badges: ["Writes data", "Production-critical"]
        )
      ]
    end

    def feature(...)
      Feature.new(...)
    end

    def ladder_step(...)
      LadderStep.new(...)
    end
  end
end
