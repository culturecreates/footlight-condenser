module Dsl
  class LibraryExpander
    Error = Class.new(StandardError)
    TOKEN = /\A\$\$([A-Z][A-Z0-9_]*)\$\$\z/
    MAX_STEPS = 1000
    MAX_DEPTH = 16
    MAX_BYTES = 1_000_000

    def self.call(algorithm, overrides: {})
      new(overrides).call(algorithm)
    end

    def initialize(overrides)
      @overrides, @entries, @steps, @origins, @evidence = overrides, nil, [], [], {}
      @bytes = 0
    end

    def call(algorithm)
      # Preserve the old split contract, including no DB access for ordinary DSL.
      raw = algorithm.split(';').map(&:strip).reject(&:empty?)
      return {steps: raw, origins: raw.map { [] }, evidence: []} unless raw.any? { |step| step.match?(TOKEN) }
      expand(raw, [])
      raise Error, "Expanded DSL exceeds #{MAX_BYTES} bytes" if @steps.sum(&:bytesize) > MAX_BYTES
      {steps: @steps, origins: @origins, evidence: @evidence.values}
    end

    private

    def expand(steps, path)
      steps.each do |step|
        match = step.match(TOKEN)
        unless match
          @bytes += step.bytesize
          raise Error, "Expanded DSL exceeds #{MAX_BYTES} bytes" if @bytes > MAX_BYTES
          @steps << step
          @origins << path.map { |item| item.slice(:name, :revision) }
          raise Error, "Expanded DSL exceeds #{MAX_STEPS} steps" if @steps.size > MAX_STEPS
          next
        end
        name = match[1]
        raise Error, "SELF_URL is a URL placeholder, not a library instruction" if name == "SELF_URL"
        raise Error, "Circular DSL library reference: #{(path.map { |item| item[:name] } + [name]).join(' -> ')}" if path.any? { |item| item[:name] == name }
        raise Error, "DSL library nesting exceeds #{MAX_DEPTH}" if path.size >= MAX_DEPTH
        @entries ||= DslLibraryEntry.pluck(:name, :body, :revision).to_h { |n,b,v| [n, {name: n, body: b, revision: v}] }.merge(@overrides)
        entry = @entries[name]
        raise Error, "Unknown DSL library instruction $$#{name}$$" unless entry
        @evidence[name] = entry.merge(sha256: Digest::SHA256.hexdigest(entry[:body]))
        expand(entry[:body].split(';').map(&:strip).reject(&:empty?), path + [entry])
      end
    end
  end
end
