namespace :test do
  desc "Run fast Distillator/Wringer replacement unit tests"
  task distillator_fast: :environment do
    files = %w[
      test/helpers/cc_wringer_helper_test.rb
      test/services/distillator/fetch_mode_test.rb
      test/services/distillator/fetch_eligibility_test.rb
      test/services/distillator/fetch_service_test.rb
      test/services/distillator/fetch_response_contract_test.rb
      test/services/dsl/wringer_client_test.rb
      test/services/dsl_algorithm_runner_test.rb
      test/services/dsl_contract_test.rb
      test/test_hygiene/unit_boundary_test.rb
    ]

    sh "bin/rails test #{files.join(' ')}"
  end
end
