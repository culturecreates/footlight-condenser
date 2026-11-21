require "test_helper"

class Distillator::TransitionMemoryTest < ActiveSupport::TestCase
  test "sample separates process resident and swap memory from cgroup file memory" do
    memory = Distillator::TransitionMemory.new(limit_mib: nil)
    memory.instance_variable_set(:@cgroup, ["/cgroup/test", 2])
    memory.stubs(:read_file).with("/proc/self/status").returns("VmRSS:\t535000 kB\nVmSwap:\t370000 kB\nVmSize:\t2600000 kB\n")
    memory.stubs(:read_file).with("/cgroup/test/memory.stat").returns("anon 409600\nfile 614400\nshmem 102400\n")
    memory.stubs(:read_file).with("/cgroup/test/memory.current").returns("1024000\n")
    memory.stubs(:read_file).with("/cgroup/test/memory.swap.current").returns(nil)
    Rails.logger.expects(:info).with do |sample|
      sample[:rss_kib] == 535000 && sample[:swap_kib] == 370000 && sample[:rss_plus_swap_kib] == 905000 &&
        sample[:virtual_kib] == 2600000 && sample[:cgroup_current_kib] == 1000 && sample[:cgroup_file_kib] == 600 &&
        sample[:cgroup_shmem_kib] == 100 && !sample.key?(:cgroup_swap_kib) && sample[:heap_live_slots].positive?
    end

    memory.record(run_id: 68, phase: "statements", completed: 40, total: 183)
  end

  test "the configured guard checks process swap even between log samples" do
    memory = Distillator::TransitionMemory.new(limit_mib: "900")
    memory.stubs(:process_metrics).returns({ rss_kib: 526 * 1024, swap_kib: 374 * 1024, rss_plus_swap_kib: 900 * 1024 })
    Rails.logger.expects(:info).with(has_entries(phase: "statements", rss_plus_swap_kib: 900 * 1024))

    error = assert_raises(Distillator::TransitionMemory::LimitExceeded) do
      memory.record(run_id: 68, phase: "statements", completed: 41, total: 183, sample: false)
    end
    assert_includes error.message, "900 MiB process memory"
  end
end
