require "minitest/autorun"
require "yaml"
require "json"

class WorkflowTrustTest < Minitest::Test
  WORKFLOWS = File.expand_path("../workflows", __dir__)
  EVENTS = {
    "app-store-metadata.yml" => ["workflow_dispatch"],
    "app-store-release.yml" => ["workflow_dispatch"],
    "app-store-reviews.yml" => ["schedule", "workflow_dispatch"],
    "app-store-screenshots.yml" => ["workflow_dispatch"],
    "app-store-signing.yml" => ["workflow_dispatch"],
    "cli-package.yml" => ["push", "workflow_dispatch"],
    "testflight.yml" => ["push"],
    "validate-automation.yml" => ["workflow_dispatch"]
  }.freeze
  IDENTITY_GATE = [
    "github.repository == 'rawcontext/luxel'",
    "github.repository_id == '1269656539'",
    "github.actor_id == '302437'",
    "github.triggering_actor == 'ccheney'"
  ].join(" && ").freeze

  def workflows
    Dir.glob(File.join(WORKFLOWS, "*.{yml,yaml}")).sort.to_h do |path|
      [File.basename(path), YAML.safe_load(File.read(path))]
    end
  end

  def test_only_owner_controlled_events_are_registered
    assert_equal EVENTS.keys.sort, workflows.keys.sort
    workflows.each do |name, workflow|
      triggers = workflow.fetch(true) # Psych parses the unquoted YAML key "on" as true.
      assert_equal EVENTS.fetch(name), triggers.keys.sort, name
      if name == "cli-package.yml"
        assert_equal({ "tags" => ["cli-v*"] }, triggers.fetch("push"))
      end
      next unless name == "testflight.yml"

      assert_equal({ "branches" => ["master"] }, triggers.fetch("push"))
    end
  end

  def test_every_job_has_a_server_side_identity_event_and_ref_gate
    workflows.each do |name, workflow|
      expected_gate = "#{IDENTITY_GATE} && #{event_gate(name)}"
      workflow.fetch("jobs").each do |job_name, job|
        gate = expected_gate
        gate += " && needs.verify_merge.outputs.authorized == 'true'" if name == "testflight.yml" && job_name != "verify_merge"
        assert_equal gate, job.fetch("if").split.join(" "), "#{name}:#{job_name}"
        assert_equal "macos-26", job.fetch("runs-on")
      end
    end
  end

  def test_checkouts_only_use_trusted_refs_from_the_same_repository
    workflows.each do |name, workflow|
      workflow.fetch("jobs").each_value do |job|
        job.fetch("steps").each do |step|
          next unless step.fetch("uses", "").start_with?("actions/checkout@")

          options = step.fetch("with", {})
          refute options.key?("repository")
          if name == "testflight.yml"
            assert_equal "${{ github.sha }}", options.fetch("ref")
          else
            refute options.key?("ref")
          end
        end
      end
    end
  end

  def test_testflight_only_accepts_an_owner_merge_into_master
    assert testflight_allowed?(owner_merge_context)

    [
      [%w[repository], "someone/luxel"],
      [%w[repository_id], "999"],
      [%w[actor_id], "999"],
      [%w[triggering_actor], "someone"],
      [%w[event_name], "pull_request"],
      [%w[event_name], "pull_request_target"],
      [%w[event_name], "workflow_dispatch"],
      [%w[ref], "refs/heads/contributor-branch"],
      [%w[needs verify_merge outputs authorized], "false"],
      [%w[needs verify_merge outputs authorized], nil]
    ].each do |path, value|
      context = owner_merge_context
      parent = path[0...-1].reduce(context) { |object, key| object.fetch(key) }
      parent[path.last] = value
      refute testflight_allowed?(context), "Unexpectedly accepted #{path.join('.')}=#{value.inspect}"
    end
  end

  def test_unit_tests_run_only_after_merge_and_gate_testflight
    jobs = workflows.fetch("testflight.yml").fetch("jobs")
    assert_equal ["verify_merge", "unit_tests"], jobs.fetch("testflight").fetch("needs")
    assert_equal "verify_merge", jobs.fetch("unit_tests").fetch("needs")
    assert_equal jobs.fetch("testflight").fetch("if"), jobs.fetch("unit_tests").fetch("if")

    workflows.each do |name, workflow|
      workflow.fetch("jobs").each do |job_name, job|
        job.fetch("steps").each do |step|
          command = step.fetch("run", "")
          next unless command.match?(/swift test|cargo test|node --test|verify_owner_merge_test.py|bazel test|_test\.rb/)

          assert_equal ["testflight.yml", "unit_tests"], [name, job_name]
        end
      end
    end
  end

  def test_build_caches_exclude_signing_material_and_do_not_skip_tests
    allowed_paths = %w[
      ~/.cache/luxel/bazel/actions
      ~/.cache/luxel/bazel/repository/content_addressable
    ]
    %w[setup-bazel save-bazel-cache].each do |name|
      path = File.expand_path("../actions/#{name}/action.yml", __dir__)
      action = YAML.safe_load(File.read(path))
      caches = action.fetch("runs").fetch("steps").select do |step|
        step.fetch("uses", "").start_with?("actions/cache/")
      end
      assert_equal allowed_paths.sort, caches.map { |step| step.fetch("with").fetch("path") }.sort
    end

    jobs = workflows.fetch("testflight.yml").fetch("jobs")
    tests = jobs.fetch("unit_tests").fetch("steps").select do |step|
      step.fetch("run", "").match?(/bazel test/)
    end
    refute_empty tests
    tests.each do |step|
      refute step.key?("if"), "Cache hits must not skip #{step.fetch('name')}"
      assert_includes step.fetch("run"), "//:tests"
      assert_includes step.fetch("run"), "//:lint"
      refute_includes step.fetch("run"), "--nocache_test_results"
    end
    %w[unit_tests testflight].each do |name|
      steps = jobs.fetch(name).fetch("steps")
      assert steps.any? { |step| step["uses"] == "./.github/actions/setup-bazel" }
      save = steps.find { |step| step["uses"] == "./.github/actions/save-bazel-cache" }
      assert_equal "always() && !cancelled()", save.fetch("if")
    end
  end

  private

  def testflight_allowed?(context)
    expression = workflows.fetch("testflight.yml").fetch("jobs").fetch("testflight").fetch("if")
    expression.split.join(" ").split(" && ").all? do |comparison|
      match = comparison.match(/\A(\w+(?:\.\w+)+) (==|!=) ('[^']*'|true|false|\d+)\z/)
      raise "Unsupported comparison: #{comparison}" unless match

      path = match[1].split(".")
      path.shift if path.first == "github"
      actual = context.dig(*path)
      next false if actual.nil?

      expected = match[3].start_with?("'") ? match[3][1...-1] : JSON.parse(match[3])
      match[2] == "==" ? actual == expected : actual != expected
    end
  end

  def owner_merge_context
    {
      "repository" => "rawcontext/luxel", "repository_id" => "1269656539",
      "actor_id" => "302437", "triggering_actor" => "ccheney",
      "event_name" => "push", "ref" => "refs/heads/master",
      "needs" => { "verify_merge" => { "outputs" => { "authorized" => "true" } } }
    }
  end

  def event_gate(name)
    case name
    when "cli-package.yml"
      "((github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/master') || " \
        "(github.event_name == 'push' && startsWith(github.ref, 'refs/tags/cli-v')))"
    when "testflight.yml"
      "github.event_name == 'push' && github.ref == 'refs/heads/master'"
    when "app-store-reviews.yml"
      "(github.event_name == 'workflow_dispatch' || github.event_name == 'schedule') && " \
        "github.ref == 'refs/heads/master'"
    else
      "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/master'"
    end
  end
end
