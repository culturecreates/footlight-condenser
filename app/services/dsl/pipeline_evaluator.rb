module Dsl
  class PipelineEvaluator
    DEFAULT_WRINGER = {
      unreachable: false,
      received_404: false,
      system_error: false,
      policy_action: nil
    }.freeze

    def self.evaluate(event:)
      new(event: event).evaluate
    end

    def initialize(event:)
      @event = event
    end

    def evaluate
      steps = pipeline_steps
      metrics = Dsl::PipelineInterpreter.new(steps).metrics
      diagnosis = Dsl::PipelineDiagnosis.new(metrics: metrics, wringer: DEFAULT_WRINGER).result

      {
        metrics: metrics,
        diagnosis: diagnosis
      }
    end

    private

    def pipeline_steps
      event_statements.each_with_index.map do |statement, index|
        {
          step: index + 1,
          type: infer_step_type(statement.source&.algorithm_value),
          output: normalize_output(statement.cache),
          error: statement_error(statement)
        }.compact
      end
    end

    def event_statements
      uri = event_identifier
      return Statement.none if uri.blank?

      Statement
        .includes(:source, :webpage)
        .where(webpages: { rdf_uri: uri })
        .where(selected_individual: true)
        .order(:id)
    end

    def event_identifier
      if @event.respond_to?(:rdf_uri)
        @event.rdf_uri
      else
        @event.to_s
      end
    end

    def infer_step_type(algorithm_value)
      expression = algorithm_value.to_s.strip
      return "unknown" if expression.blank?

      left_side = expression.split("=").first.to_s.strip.downcase
      left_side.presence || "unknown"
    end

    def normalize_output(value)
      string_value = value.to_s.strip
      return nil if string_value.empty?

      if string_value.start_with?("[") && string_value.end_with?("]")
        begin
          parsed = JSON.parse(string_value)
          return parsed if parsed.is_a?(Array)
        rescue JSON::ParserError
          # Keep the original value when cache is not valid JSON.
        end
      end

      value
    end

    def statement_error(statement)
      return nil unless statement.is_a?(Statement)
      return "statement_problem" if statement.status.to_s == "problem"
      return "statement_error_cache" if statement.cache.to_s.downcase.include?("error:")

      nil
    end
  end
end
