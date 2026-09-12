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
    "testflight.yml" => ["pull_request_target"],
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

      assert_equal({ "types" => ["closed"], "branches" => ["master"] }, triggers.fetch("pull_request_target"))
    end
  end

  def test_every_job_has_a_server_side_identity_event_and_ref_gate
    workflows.each do |name, workflow|
      expected_gate = "#{IDENTITY_GATE} && #{event_gate(name)}"
      workflow.fetch("jobs").each do |job_name, job|
        assert_equal expected_gate, job.fetch("if").split.join(" "), "#{name}:#{job_name}"
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
            assert_equal "${{ github.event.pull_request.merge_commit_sha }}", options.fetch("ref")
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
      [%w[event_name], "push"],
      [%w[event_name], "workflow_dispatch"],
      [%w[ref], "refs/heads/contributor-branch"],
      [%w[event action], "opened"],
      [%w[event action], "synchronize"],
      [%w[event pull_request merged], false],
      [%w[event pull_request merged_by id], 999],
      [%w[event pull_request base ref], "develop"],
      [%w[event pull_request base repo id], 999],
      [%w[event pull_request merge_commit_sha], ""],
      [%w[event pull_request merge_commit_sha], nil]
    ].each do |path, value|
      context = owner_merge_context
      parent = path[0...-1].reduce(context) { |object, key| object.fetch(key) }
      parent[path.last] = value
      refute testflight_allowed?(context), "Unexpectedly accepted #{path.join('.')}=#{value.inspect}"
    end
  end

  private

  def testflight_allowed?(context)
    expression = workflows.fetch("testflight.yml").fetch("jobs").fetch("testflight").fetch("if")
    expression.split.join(" ").split(" && ").all? do |comparison|
      match = comparison.match(/\A(\w+(?:\.\w+)+) (==|!=) ('[^']*'|true|false|\d+)\z/)
      raise "Unsupported comparison: #{comparison}" unless match

      actual = context.dig(*match[1].split(".").drop(1))
      next false if actual.nil?

      expected = match[3].start_with?("'") ? match[3][1...-1] : JSON.parse(match[3])
      match[2] == "==" ? actual == expected : actual != expected
    end
  end

  def owner_merge_context
    {
      "repository" => "rawcontext/luxel", "repository_id" => "1269656539",
      "actor_id" => "302437", "triggering_actor" => "ccheney",
      "event_name" => "pull_request_target", "ref" => "refs/heads/master",
      "event" => {
        "action" => "closed",
        "pull_request" => {
          "merged" => true, "merged_by" => { "id" => 302437 },
          "base" => { "ref" => "master", "repo" => { "id" => 1269656539 } },
          "merge_commit_sha" => "a" * 40
        }
      }
    }
  end

  def event_gate(name)
    case name
    when "cli-package.yml"
      "((github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/master') || " \
        "(github.event_name == 'push' && startsWith(github.ref, 'refs/tags/cli-v')))"
    when "testflight.yml"
      [
        "github.event_name == 'pull_request_target'",
        "github.event.action == 'closed'",
        "github.ref == 'refs/heads/master'",
        "github.event.pull_request.merged == true",
        "github.event.pull_request.merged_by.id == 302437",
        "github.event.pull_request.base.ref == 'master'",
        "github.event.pull_request.base.repo.id == 1269656539",
        "github.event.pull_request.merge_commit_sha != ''"
      ].join(" && ")
    when "app-store-reviews.yml"
      "(github.event_name == 'workflow_dispatch' || github.event_name == 'schedule') && " \
        "github.ref == 'refs/heads/master'"
    else
      "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/master'"
    end
  end
end
