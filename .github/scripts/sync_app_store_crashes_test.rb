# frozen_string_literal: true

require "minitest/autorun"
require_relative "sync_app_store_crashes"

class AppStoreCrashSyncTest < Minitest::Test
  def test_fetches_every_build_signature_log_and_testflight_crash
    calls = []
    get = lambda do |url, token|
      calls << [url, token]
      response_for(url)
    end

    builds = AppStoreCrashSync.fetch_builds(app_id: "6800438206", token: "token", get: get)
    diagnostics = AppStoreCrashSync.fetch_diagnostics(builds: builds, token: "token", get: get)
    crashes = AppStoreCrashSync.fetch_testflight_crashes(app_id: "6800438206", token: "token", get: get)

    assert_equal %w[build-1 build-2], builds.map { |build| build["id"] }
    assert_equal %w[signature-1 signature-2], diagnostics.map { |record| record["signature"]["id"] }
    assert_equal "log data", diagnostics.first["logs"]["productData"].first["value"]
    assert_equal ["crash-1"], crashes.map { |record| record["submission"]["id"] }
    assert_equal "complete crash log", crashes.first["crashLog"]["attributes"]["logText"]
    assert calls.all? { |_, token| token == "token" }
    refute calls.any? { |url, _| url.include?("filter%5BdiagnosticType%5D") }
  end

  def test_entries_include_readable_fields_and_raw_data_metadata
    diagnostic = AppStoreCrashSync.entry(diagnostic_record)
    crash = AppStoreCrashSync.entry(testflight_record)

    assert_includes diagnostic[:title], "HANGS"
    assert_includes diagnostic[:body], "MainActor.run"
    assert_includes diagnostic[:body], "Build details"
    assert_includes diagnostic[:raw], "callStackTree"
    assert_includes crash[:title], "TestFlight Crash"
    assert_includes crash[:body], "Please fix this"
    assert_includes crash[:body], "tester@example.com"
    assert_includes crash[:raw], "complete crash log"
    assert_match(/app-store-raw-data-sha256:[a-f0-9]{64}/, crash[:body])
  end

  def test_raw_data_chunks_preserve_unicode_and_respect_limit
    value = ("🙂 crash line\n" * 20)
    chunks = AppStoreConnectSupport.utf8_chunks(value, maximum_bytes: 31)

    assert_equal value, chunks.join
    assert chunks.all?(&:valid_encoding?)
    assert chunks.all? { |chunk| chunk.bytesize <= 31 }
  end

  def test_missing_diagnostics_are_treated_as_no_available_data
    get = lambda do |_url, _token|
      raise AppStoreConnectSupport::RequestError.new(404, "No diagnostics for this build")
    end

    diagnostics = AppStoreCrashSync.fetch_diagnostics(builds: [build], token: "token", get: get)

    assert_empty diagnostics
  end

  private

  def response_for(url)
    case url
    when %r{/apps/6800438206/builds}
      { "data" => [build("build-1")], "links" => { "next" => "https://example.test/builds-next" } }
    when "https://example.test/builds-next"
      { "data" => [build("build-2")], "links" => {} }
    when %r{/builds/build-1/diagnosticSignatures}
      { "data" => [signature("signature-1")], "links" => {} }
    when %r{/builds/build-2/diagnosticSignatures}
      { "data" => [signature("signature-2")], "links" => {} }
    when %r{/diagnosticSignatures/}
      { "productData" => [{ "value" => "log data" }] }
    when %r{/apps/6800438206/betaFeedbackCrashSubmissions}
      {
        "data" => [submission],
        "included" => [build("build-1"), tester],
        "links" => {}
      }
    when %r{/betaFeedbackCrashSubmissions/crash-1/crashLog}
      { "data" => crash_log }
    else
      raise "Unexpected URL: #{url}"
    end
  end

  def build(id = "build-1")
    {
      "type" => "builds",
      "id" => id,
      "attributes" => { "version" => "42", "uploadedDate" => "2026-08-13T12:00:00Z" }
    }
  end

  def signature(id = "signature-1")
    {
      "type" => "diagnosticSignatures",
      "id" => id,
      "attributes" => {
        "diagnosticType" => "HANGS",
        "signature" => "Luxel: MainActor.run + 10",
        "weight" => 0.75
      }
    }
  end

  def submission
    {
      "type" => "betaFeedbackCrashSubmissions",
      "id" => "crash-1",
      "attributes" => {
        "createdDate" => "2026-08-13T12:00:00Z",
        "comment" => "Please fix this",
        "email" => "tester@example.com",
        "deviceModel" => "Mac16,1",
        "osVersion" => "26.0",
        "appPlatform" => "MAC_OS"
      },
      "relationships" => {
        "build" => { "data" => { "type" => "builds", "id" => "build-1" } },
        "tester" => { "data" => { "type" => "betaTesters", "id" => "tester-1" } }
      }
    }
  end

  def tester
    {
      "type" => "betaTesters",
      "id" => "tester-1",
      "attributes" => { "email" => "tester@example.com", "state" => "INSTALLED" }
    }
  end

  def crash_log
    {
      "type" => "betaCrashLogs",
      "id" => "crash-log-1",
      "attributes" => { "logText" => "complete crash log" }
    }
  end

  def diagnostic_record
    {
      "kind" => "diagnostic",
      "build" => build,
      "signature" => signature,
      "logs" => { "productData" => [{ "callStackTree" => ["MainActor.run"] }] }
    }
  end

  def testflight_record
    {
      "kind" => "testflightCrash",
      "submission" => submission,
      "build" => build,
      "tester" => tester,
      "crashLog" => crash_log
    }
  end
end
