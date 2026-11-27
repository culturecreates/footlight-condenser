require "digest"
require "concurrent/atomic/atomic_fixnum"

module Dsl
  class RubyWarnings
    CONTEXT_KEY = :footlight_dsl_ruby_warnings
    SUMMARY_INTERVAL = 100
    REPEATED_DEFINITIONS = Concurrent::AtomicFixnum.new(0)
    REDEFINITION = /\A(\d+): warning: already initialized constant Dsl::Core::AlgorithmRunner::([[:upper:]][[:alnum:]_]*)\n\z/

    def self.evaluate(binding, code)
      previous = Thread.current[CONTEXT_KEY]
      warnings = new(code)
      Thread.current[CONTEXT_KEY] = warnings
      binding.eval(code, warnings.filename)
    ensure
      Thread.current[CONTEXT_KEY] = previous
    end

    attr_reader :filename

    def initialize(code)
      @filename = "(footlight-dsl:#{Digest::SHA256.hexdigest(code)})"
    end

    def count_if_repeated_definition(message)
      return false unless message.is_a?(String)

      if message == @previous_definition
        @previous_definition = nil
        return true
      end
      return false unless message.start_with?("#{@filename}:")

      match = REDEFINITION.match(message.delete_prefix("#{@filename}:"))
      return false unless match

      line, constant = match.captures
      # MRI warns before updating the constant's original source location.
      return false unless Dsl::Core::AlgorithmRunner.const_source_location(constant, false) == [@filename, line.to_i]

      @previous_definition = "#{@filename}:#{line}: warning: previous definition of #{constant} was here\n"
      total = REPEATED_DEFINITIONS.increment
      if (total % SUMMARY_INTERVAL).zero?
        Rails.logger.warn(event: "dsl.ruby.constant_redefinitions", suppressed_redefinitions: total)
      end
      true
    end
  end
end
