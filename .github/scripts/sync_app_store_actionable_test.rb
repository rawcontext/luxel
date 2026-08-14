# frozen_string_literal: true

require "minitest/autorun"
require_relative "sync_app_store_actionable"

class AppStoreActionableSyncTest < Minitest::Test
  def test_fetches_all_screenshot_feedback_with_build_and_tester
    get = lambda do |url, _token|
      if url.include?("betaFeedbackScreenshotSubmissions")
        {
          "data" => [screenshot_submission],
          "included" => [build, tester],
          "links" => {}
        }
      else
        raise "Unexpected URL: #{url}"
      end
    end

    records = AppStoreActionableSync.fetch_screenshot_feedback(app_id: "6800438206", token: "token", get: get)

    assert_equal ["feedback-1"], records.map { |record| record["submission"]["id"] }
    assert_equal "42", records.first["build"]["attributes"]["version"]
    assert_equal "tester@example.com", records.first["tester"]["attributes"]["email"]
  end

  def test_screenshot_issue_contains_image_comment_metadata_and_raw_data
    item = AppStoreActionableSync.entry(
      "kind" => "screenshotFeedback",
      "submission" => screenshot_submission,
      "build" => build,
      "tester" => tester
    )

    assert_includes item[:title], "TestFlight Feedback"
    assert_includes item[:body], "Please fix the toolbar"
    assert_includes item[:body], "![TestFlight feedback screenshot 1](https://example.test/screenshot.png)"
    assert_includes item[:body], "Battery Percentage"
    assert_includes item[:body], "tester@example.com"
    assert_includes item[:raw], "appUptimeInMilliseconds"
    assert_match(/app-store-raw-data-sha256:[a-f0-9]{64}/, item[:body])
  end

  def test_uses_only_apple_generated_performance_regressions
    response = {
      "insights" => {
        "regressions" => [performance_insight],
        "trendingUp" => [{ "metric" => "memory" }]
      },
      "productData" => [
        {
          "platform" => "macOS",
          "metricCategories" => [
            { "identifier" => "LAUNCH", "metrics" => [{ "identifier" => "launchTime", "datasets" => [] }] }
          ]
        }
      ]
    }
    records = AppStoreActionableSync.fetch_performance_regressions(
      app_id: "6800438206",
      token: "token",
      get: ->(_url, _token) { response }
    )
    item = AppStoreActionableSync.entry(records.first)

    assert_equal 1, records.length
    assert_equal "launchTime", records.first["insight"]["metric"]
    assert_equal "launchTime", records.first["metricData"].first["metrics"].first["identifier"]
    assert_includes item[:body], "Increased 25%"
    assert_includes item[:body], "High impact"
    assert_includes item[:body], "25%"
  end

  def test_fetches_failed_uploads_and_apple_rejections_without_developer_rejections
    calls = []
    get = lambda do |url, _token|
      calls << url
      case url
      when /buildUploads/
        { "data" => [failed_upload], "included" => [build], "links" => {} }
      when /appStoreVersions/
        { "data" => [rejected_version], "included" => [build], "links" => {} }
      else
        raise "Unexpected URL: #{url}"
      end
    end

    uploads = AppStoreActionableSync.fetch_failed_uploads(app_id: "6800438206", token: "token", get: get)
    rejections = AppStoreActionableSync.fetch_app_store_rejections(app_id: "6800438206", token: "token", get: get)
    upload_item = AppStoreActionableSync.entry(uploads.first)
    rejection_item = AppStoreActionableSync.entry(rejections.first)

    assert_includes calls.first, "filter%5Bstate%5D=FAILED"
    assert_includes calls.last, "INVALID_BINARY%2CMETADATA_REJECTED%2CREJECTED"
    refute_includes calls.last, "DEVELOPER_REJECTED"
    assert_includes upload_item[:body], "ITMS-90000"
    assert_includes upload_item[:body], "Invalid binary"
    assert_includes rejection_item[:title], "METADATA_REJECTED"
  end

  def test_fetches_testflight_rejections_for_the_apps_builds
    calls = []
    get = lambda do |url, _token|
      calls << url
      {
        "data" => [beta_rejection],
        "included" => [build],
        "links" => {}
      }
    end

    records = AppStoreActionableSync.fetch_testflight_rejections(builds: [build], token: "token", get: get)
    item = AppStoreActionableSync.entry(records.first)

    assert_equal 1, records.length
    assert_includes calls.first, "filter%5Bbuild%5D=build-1"
    assert_includes calls.first, "filter%5BbetaReviewState%5D=REJECTED"
    assert_includes item[:title], "TestFlight Rejection"
    assert_includes item[:body], "Submitted Date"
  end

  private

  def screenshot_submission
    {
      "type" => "betaFeedbackScreenshotSubmissions",
      "id" => "feedback-1",
      "attributes" => {
        "createdDate" => "2026-08-13T12:00:00Z",
        "comment" => "Please fix the toolbar",
        "email" => "tester@example.com",
        "deviceModel" => "Mac16,1",
        "osVersion" => "26.0",
        "appPlatform" => "MAC_OS",
        "batteryPercentage" => 82,
        "appUptimeInMilliseconds" => 12_345,
        "screenshots" => [
          {
            "url" => "https://example.test/screenshot.png",
            "width" => 1512,
            "height" => 982,
            "expirationDate" => "2026-08-14T12:00:00Z"
          }
        ]
      },
      "relationships" => {
        "build" => { "data" => { "type" => "builds", "id" => "build-1" } },
        "tester" => { "data" => { "type" => "betaTesters", "id" => "tester-1" } }
      }
    }
  end

  def build
    {
      "type" => "builds",
      "id" => "build-1",
      "attributes" => { "version" => "42", "uploadedDate" => "2026-08-13T10:00:00Z" }
    }
  end

  def tester
    {
      "type" => "betaTesters",
      "id" => "tester-1",
      "attributes" => { "email" => "tester@example.com", "state" => "INSTALLED" }
    }
  end

  def performance_insight
    {
      "metricCategory" => "LAUNCH",
      "metric" => "launchTime",
      "latestVersion" => "1.2",
      "referenceVersions" => ["1.0", "1.1"],
      "maxLatestVersionValue" => 2000,
      "highImpact" => true,
      "summaryString" => "Increased 25% compared with previous versions.",
      "populations" => [
        {
          "device" => "all_macs",
          "percentile" => "percentile.ninety",
          "latestVersionValue" => 2000,
          "referenceAverageValue" => 1600,
          "deltaPercentage" => 25,
          "summaryString" => "Increased 25%"
        }
      ]
    }
  end

  def failed_upload
    {
      "type" => "buildUploads",
      "id" => "upload-1",
      "attributes" => {
        "cfBundleShortVersionString" => "1.2",
        "cfBundleVersion" => "42",
        "platform" => "MAC_OS",
        "state" => {
          "state" => "FAILED",
          "errors" => [{ "code" => "ITMS-90000", "description" => "Invalid binary" }]
        }
      },
      "relationships" => { "build" => { "data" => { "type" => "builds", "id" => "build-1" } } }
    }
  end

  def rejected_version
    {
      "type" => "appStoreVersions",
      "id" => "version-1",
      "attributes" => {
        "versionString" => "1.2",
        "platform" => "MAC_OS",
        "appVersionState" => "METADATA_REJECTED"
      },
      "relationships" => { "build" => { "data" => { "type" => "builds", "id" => "build-1" } } }
    }
  end

  def beta_rejection
    {
      "type" => "betaAppReviewSubmissions",
      "id" => "beta-review-1",
      "attributes" => { "betaReviewState" => "REJECTED", "submittedDate" => "2026-08-13T11:00:00Z" },
      "relationships" => { "build" => { "data" => { "type" => "builds", "id" => "build-1" } } }
    }
  end
end
