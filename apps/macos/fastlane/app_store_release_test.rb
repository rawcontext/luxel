# frozen_string_literal: true

require "minitest/autorun"

class ReleaseLaneHarness
  module UI
    def self.user_error!(message)
      raise message
    end
  end

  module Spaceship
    module ConnectAPI
      module Platform
        MAC_OS = "MAC_OS"
      end

      class App
        class << self
          attr_accessor :instance

          def find(identifier)
            raise "Wrong app" unless identifier == "com.rawcontext.luxel"
            instance
          end
        end

        def initialize(version)
          @version = version
        end

        def ensure_version!(version, platform:)
          raise "Wrong version" unless version == "1.4.0" && platform == Platform::MAC_OS
        end

        def get_app_store_versions(filter:, includes:)
          ensure_version!(filter.fetch(:versionString), platform: filter.fetch(:platform))
          [@version.call(includes)]
        end
      end

      class AppStoreVersion
        module ReleaseType
          AFTER_APPROVAL = "AFTER_APPROVAL"
        end

        class << self
          attr_accessor :reader

          def get(app_store_version_id:, includes:)
            raise "Wrong version ID" unless app_store_version_id == "version-140"
            reader.call(includes)
          end
        end
      end
    end
  end

  class << self
    attr_reader :lanes

    def default_platform(*) = nil
    def desc(*) = nil
    def platform(*) = yield

    def lane(name, &block)
      (@lanes ||= {})[name] = block
    end
  end

  fastfile = File.expand_path("Fastfile", __dir__)
  class_eval(File.read(fastfile), fastfile)

  attr_reader :submission

  def app_store_connect_api_key_from_env = :test_api_key
  def update_app_review_notes!(_version) = nil

  def upload_to_app_store(**options)
    @submission = options
  end

  def submit
    instance_exec({ app_version: "1.4.0", build_number: "202609120001" }, &self.class.lanes.fetch(:submit_app_store_release))
  end
end

class AppStoreReleaseTest < Minitest::Test
  Version = Struct.new(:id, :version_string, :release_type, :app_store_version_phased_release, :writer) do
    def update(attributes:)
      writer.call(attributes)
    end
  end

  PhasedRelease = Struct.new(:remover) do
    def delete! = remover.call
  end

  def setup
    @lane = ReleaseLaneHarness.new
    @remote = { release_type: "MANUAL", phased_release: nil, copyright: "Existing copyright", description: "Existing listing" }
    @writes = []
    @reads = []
    @persist_release = true
    @persist_removal = true
    @update_error = nil
    reader = lambda do |includes|
      @reads << @remote.dup
      phase = @remote[:phased_release] if includes == "appStoreVersionPhasedRelease"
      Version.new("version-140", "1.4.0", @remote[:release_type], phase, lambda do |attributes|
        raise @update_error if @update_error
        @writes << attributes
        @remote[:release_type] = attributes.fetch(:releaseType) if @persist_release
      end)
    end
    api = ReleaseLaneHarness::Spaceship::ConnectAPI
    api::App.instance = api::App.new(reader)
    api::AppStoreVersion.reader = reader
  end

  def test_manual_draft_is_verified_for_automatic_release_before_submission
    @lane.submit

    assert_equal [{ releaseType: "AFTER_APPROVAL" }], @writes
    assert_equal "AFTER_APPROVAL", @remote[:release_type]
    assert_equal "AFTER_APPROVAL", @reads.last[:release_type]
    assert_nil @reads.last[:phased_release]
    assert_equal "Existing copyright", @remote[:copyright]
    assert_equal "Existing listing", @remote[:description]
    assert_equal true, @lane.submission.fetch(:submit_for_review)
    assert_equal true, @lane.submission.fetch(:skip_metadata)
    assert_equal true, @lane.submission.fetch(:skip_screenshots)
    assert_equal true, @lane.submission.fetch(:skip_binary_upload)
    assert_equal true, @lane.submission.fetch(:skip_app_version_update)
    assert_equal "1.4.0", @lane.submission.fetch(:app_version)
    assert_equal "202609120001", @lane.submission.fetch(:build_number)
    refute @lane.submission.key?(:automatic_release)
    refute @lane.submission.key?(:phased_release)
  end

  def test_existing_phased_rollout_is_removed_and_verified_before_submission
    enable_phased_release
    @lane.submit

    assert_nil @remote[:phased_release]
    assert_nil @reads.last[:phased_release]
    assert_equal "AFTER_APPROVAL", @reads.last[:release_type]
    refute_nil @lane.submission
  end

  def test_release_policy_update_failure_prevents_submission
    @update_error = "App Store Connect rejected the update"
    error = assert_raises(RuntimeError) { @lane.submit }

    assert_equal @update_error, error.message
    assert_nil @lane.submission
  end

  def test_manual_release_readback_prevents_submission
    @persist_release = false
    error = assert_raises(RuntimeError) { @lane.submit }

    assert_match(/automatic release/, error.message)
    assert_nil @lane.submission
  end

  def test_phased_rollout_readback_prevents_submission
    enable_phased_release
    @persist_removal = false
    error = assert_raises(RuntimeError) { @lane.submit }

    assert_match(/phased release/, error.message)
    assert_nil @lane.submission
  end

  private

  def enable_phased_release
    @remote[:phased_release] = PhasedRelease.new(lambda do
      @remote[:phased_release] = nil if @persist_removal
    end)
  end
end
