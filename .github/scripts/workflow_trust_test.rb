require "minitest/autorun"
require "yaml"

class WorkflowTrustTest < Minitest::Test
  WORKFLOWS = File.expand_path("../workflows", __dir__)
  EVENTS = {
    "app-store-metadata.yml" => ["workflow_dispatch"],
    "app-store-release.yml" => ["workflow_dispatch"],
    "app-store-reviews.yml" => ["schedule", "workflow_dispatch"],
    "app-store-screenshots.yml" => ["workflow_dispatch"],
    "app-store-signing.yml" => ["workflow_dispatch"],
    "testflight.yml" => ["push", "workflow_dispatch"],
    "validate-automation.yml" => ["workflow_dispatch"]
  }.freeze
  IDENTITY_GATE = [
    "github.repository == 'ccheney/luxel'",
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
      next unless triggers.key?("push")

      assert_equal({ "tags" => ["v*"] }, triggers.fetch("push"), name)
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

  def test_checkouts_cannot_redirect_to_a_pull_request_or_another_repository
    workflows.each_value do |workflow|
      workflow.fetch("jobs").each_value do |job|
        job.fetch("steps").each do |step|
          next unless step.fetch("uses", "").start_with?("actions/checkout@")

          options = step.fetch("with", {})
          refute options.key?("repository")
          refute options.key?("ref")
        end
      end
    end
  end

  private

  def event_gate(name)
    case name
    when "testflight.yml"
      "((github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/master') || " \
        "((github.event_name == 'push' || github.event_name == 'workflow_dispatch') && " \
        "startsWith(github.ref, 'refs/tags/v')))"
    when "app-store-reviews.yml"
      "(github.event_name == 'workflow_dispatch' || github.event_name == 'schedule') && " \
        "github.ref == 'refs/heads/master'"
    else
      "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/master'"
    end
  end
end
