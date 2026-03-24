module Dsl
  class PipelineEvaluator
    DEFAULT_WRINGER = {
      unreachable: false,
      received_404: false,
      system_error: false,
      policy_action: nil
    }.freeze

    def self.evaluate(event:, wringer: nil)
      new(event: event, wringer: wringer).evaluate
    end

    def initialize(event:, wringer: nil)
      @event = event
      @wringer = normalize_wringer(wringer)
    end

    def evaluate
      steps = pipeline_steps
      metrics = Dsl::PipelineInterpreter.new(steps).metrics
      diagnosis = Dsl::PipelineDiagnosis.new(metrics: metrics, wringer: effective_wringer, steps: steps).result

      {
        metrics: metrics,
        diagnosis: diagnosis
      }
    end

    private

    def pipeline_steps
      step_counter = 0

      event_statements.flat_map do |statement|
        step_types = extract_step_types(statement.source&.algorithm_value)
        next [] if step_types.empty?

        output = normalize_output(statement.cache)
        error = statement_error(statement)

        step_types.map do |step_type|
          step_counter += 1
          {
            step: step_counter,
            type: step_type,
            primitive: infer_primitive(step_type),
            output: output,
            error: error
          }.compact
        end
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

    def extract_step_types(algorithm_value)
      expression = algorithm_value.to_s
      return [] if expression.blank?

      expression.split(";").map(&:strip).reject(&:blank?).filter_map do |segment|
        segment.split("=", 2).first.to_s.strip.downcase.presence
      end
    end

    def infer_primitive(type)
      t = type.to_s

      return :branch if t.start_with?("if_xpath")
      return :extract if t.include?("xpath")
      return :navigate if t.include?("url")
      return :transform if t.include?("ruby")
      return :transform if t.include?("sparql")

      :unknown
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

    def normalize_wringer(value)
      return {} unless value.respond_to?(:to_h)

      hash = value.to_h
      hash.is_a?(Hash) ? hash.symbolize_keys : {}
    end

    def effective_wringer
      DEFAULT_WRINGER.merge(@wringer.slice(:unreachable, :received_404, :system_error, :policy_action))
    end
  end
end
