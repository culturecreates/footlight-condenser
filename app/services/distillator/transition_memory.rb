require "securerandom"

module Distillator
  class TransitionMemory
    class LimitExceeded < StandardError; end
    WORKER_BOOT_ID = SecureRandom.uuid.freeze

    PROCESS_FIELDS = { "VmRSS" => :rss_kib, "VmSwap" => :swap_kib, "VmSize" => :virtual_kib,
      "VmHWM" => :peak_rss_kib }.freeze
    HEAP_FIELDS = %i[heap_live_slots heap_free_slots heap_allocated_pages old_objects minor_gc_count major_gc_count].freeze
    V2_FIELDS = { "anon" => :cgroup_anon_kib, "file" => :cgroup_file_kib,
      "shmem" => :cgroup_shmem_kib }.freeze
    V1_FIELDS = { "total_rss" => :cgroup_rss_kib, "total_swap" => :cgroup_swap_kib,
      "total_cache" => :cgroup_file_kib }.freeze

    def initialize(limit_mib: ENV["DISTILLATOR_TRANSITION_MEMORY_LIMIT_MIB"])
      limit = Integer(limit_mib.to_s, exception: false)
      @limit_kib = limit * 1024 if limit&.positive?
      @cgroup = cgroup_directory
    end

    def record(run_id:, phase:, completed: nil, total: nil, sample: true, profile: nil, enforce_limit: true)
      return unless sample || @limit_kib

      metrics = process_metrics
      used_kib = metrics[:rss_plus_swap_kib] || metrics[:rss_kib]
      exceeded = enforce_limit && @limit_kib && used_kib && used_kib >= @limit_kib
      if sample || exceeded
        stats = metrics.merge(GC.stat.slice(*HEAP_FIELDS)).merge(cgroup_metrics)
        Rails.logger.info({ event: "distillator.transition.memory", pid: Process.pid, worker_boot_id: WORKER_BOOT_ID,
          dyno: ENV["DYNO"], run_id: run_id, phase: phase,
          completed: completed, total: total, process_memory_limit_kib: @limit_kib, profile: profile }.compact.merge(stats))
      end
      return unless exceeded

      raise LimitExceeded, "Transition stopped during #{phase} at #{used_kib / 1024} MiB process memory " \
        "(configured limit #{@limit_kib / 1024} MiB). This check is incomplete."
    end

    private

    def process_metrics
      metrics = read_file("/proc/self/status").to_s.each_line.with_object({}) do |line, values|
        field, value = line.split(":", 2)
        next unless (key = PROCESS_FIELDS[field])

        values[key] = Integer(value.split.first, exception: false)
      end.compact
      if metrics.key?(:rss_kib) && metrics.key?(:swap_kib)
        metrics[:rss_plus_swap_kib] = metrics[:rss_kib] + metrics[:swap_kib]
      end
      metrics
    end

    def cgroup_directory
      read_file("/proc/self/cgroup").to_s.each_line do |line|
        _, controllers, path = line.strip.split(":", 3)
        next unless path&.start_with?("/")

        if controllers == ""
          base, version = "/sys/fs/cgroup", 2
        elsif controllers.to_s.split(",").include?("memory")
          base, version = "/sys/fs/cgroup/memory", 1
        else
          next
        end
        directory = File.join(base, path)
        return [directory, version] if File.readable?(File.join(directory, "memory.stat"))
      end
      nil
    end

    def cgroup_metrics
      return {} unless @cgroup

      directory, version = @cgroup
      names = version == 2 ? V2_FIELDS : V1_FIELDS
      metrics = read_file(File.join(directory, "memory.stat")).to_s.each_line.with_object({}) do |line, values|
        field, bytes = line.split
        values[names.fetch(field)] = bytes.to_i / 1024 if names.key?(field)
      end
      return {} if metrics.empty?

      metrics[:cgroup_version] = version
      if version == 2
        metrics[:cgroup_current_kib] = read_kib(File.join(directory, "memory.current"))
        metrics[:cgroup_swap_kib] = read_kib(File.join(directory, "memory.swap.current"))
      end
      metrics.compact
    end

    def read_kib(path)
      bytes = Integer(read_file(path).to_s, exception: false)
      bytes / 1024 if bytes
    end

    def read_file(path)
      File.read(path)
    rescue SystemCallError
      nil
    end
  end
end
