class RefreshPreprocessingStatementJob < ApplicationJob
  queue_as :default

  def perform(policy_id, run_id)
    Preprocessing::Runner.call(policy_id, run_id)
  end
end
