namespace :test do
  desc "Run fast Distillator/Wringer replacement unit tests"
  task distillator_fast: :environment do
    files = %w[
      test/helpers/cc_wringer_helper_test.rb
      test/services/distillator/fetch_mode_test.rb
      test/services/distillator/fetch_eligibility_test.rb
      test/services/distillator/fetch_service_test.rb
      test/services/distillator/p0_transition_safety_test.rb
      test/services/distillator/fetch_cache_encoding_test.rb
      test/services/distillator/html_content_test.rb
      test/services/distillator/website_operation_status_test.rb
      test/models/distillator/transition_run_test.rb
      test/services/distillator/statement_parity_check_test.rb
      test/services/distillator/p1_persistence_test.rb
      test/services/distillator/p1_navigation_test.rb
      test/services/distillator/p1_queue_health_test.rb
      test/services/distillator/production_preflight_test.rb
      test/services/distillator/transition_check_runner_test.rb
      test/services/distillator/rollout_transition_test.rb
      test/controllers/distillator/transition_checks_controller_test.rb
      test/controllers/distillator/active_transition_report_test.rb
      test/services/distillator/fetch_response_contract_test.rb
      test/services/dsl/wringer_client_test.rb
      test/services/dsl_algorithm_runner_test.rb
      test/services/dsl_contract_test.rb
      test/test_hygiene/unit_boundary_test.rb
    ]

    sh "bin/rails test #{files.join(' ')}"
  end
end
