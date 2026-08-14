# frozen_string_literal: true

require "minitest/autorun"
require_relative "sync_app_store_digests"

class AppStoreDigestSyncTest < Minitest::Test
  def test_aggregates_testflight_adoption_for_each_build
    response = {
      "data" => [
        {
          "dataPoints" => [
            { "values" => { "inviteCount" => 10, "installCount" => 7, "sessionCount" => 12 } },
            { "values" => { "crashCount" => 2, "feedbackCount" => 3 } }
          ]
        }
      ]
    }

    adoption = AppStoreDigestSync.fetch_testflight_adoption(
      builds: [build],
      token: "token",
      get: ->(_url, _token) { response }
    )

    assert_equal 7, adoption.first["values"]["installCount"]
    assert_equal 12, adoption.first["values"]["sessionCount"]
    assert_equal 2, adoption.first["values"]["crashCount"]
    assert_equal 3, adoption.first["values"]["feedbackCount"]
  end

  def test_creates_ongoing_analytics_request_and_downloads_latest_weekly_report
    calls = []
    get = lambda do |url, _token|
      calls << url
      case url
      when /apps\/6800438206\/analyticsReportRequests/
        { "data" => [], "links" => {} }
      when /analyticsReportRequests\/request-1\/reports/
        { "data" => [analytics_report], "links" => {} }
      when /analyticsReports\/report-1\/instances/
        {
          "data" => [
            analytics_instance("old", "2026-08-01"),
            analytics_instance("latest", "2026-08-08")
          ],
          "links" => {}
        }
      when /analyticsReportInstances\/latest\/segments/
        { "data" => [analytics_segment], "links" => {} }
      else
        raise "Unexpected URL: #{url}"
      end
    end
    posted = nil
    post = lambda do |_url, _token, payload|
      posted = payload
      { "data" => { "type" => "analyticsReportRequests", "id" => "request-1" } }
    end
    download = ->(_url, token: nil) { "Event\tCounts\nImpression\t10\nProduct Page View\t4\n" }

    analytics = AppStoreDigestSync.fetch_analytics(
      app_id: "6800438206",
      granularity: "WEEKLY",
      token: "token",
      output_dir: "",
      get: get,
      post: post,
      download: download
    )

    assert_equal "ONGOING", posted.dig("data", "attributes", "accessType")
    assert_equal "6800438206", posted.dig("data", "relationships", "app", "data", "id")
    assert_equal "Available", analytics["status"]
    assert_equal "2026-08-08", analytics["reports"].first["processingDate"]
    assert_equal 2, analytics["reports"].first["rows"].length
    assert calls.any? { |url| url.include?("filter%5Bgranularity%5D=WEEKLY") }
    refute calls.any? { |url| url.include?("analyticsReportInstances/old") }
  end

  def test_summarizes_analytics_adoption_sales_and_finance_in_digest
    analytics = {
      "status" => "Available",
      "reports" => [
        {
          "name" => "App Store Discovery and Engagement Standard",
          "category" => "APP_STORE_ENGAGEMENT",
          "processingDate" => "2026-08-08",
          "segmentCount" => 1,
          "rows" => [
            { "Event" => "Impression", "Counts" => "10" },
            { "Event" => "Product Page View", "Counts" => "4" }
          ]
        },
        {
          "name" => "App Sessions Standard",
          "category" => "APP_USAGE",
          "processingDate" => "2026-08-08",
          "segmentCount" => 1,
          "rows" => [{ "Sessions" => "5", "Total Session Duration" => "100" }]
        }
      ]
    }
    adoption = [{ "build" => build, "values" => { "installCount" => 7, "sessionCount" => 12 } }]
    sales = {
      "status" => "Available",
      "rows" => [
        { "Units" => "10", "Developer Proceeds" => "1.50", "Currency of Proceeds" => "USD" },
        { "Units" => "-2", "Developer Proceeds" => "1.50", "Currency of Proceeds" => "USD" }
      ]
    }
    finance = {
      "status" => "Available for Apple fiscal month 2026-07",
      "rows" => [
        {
          "Quantity" => "8",
          "Sale or Return" => "S",
          "Extended Partner Share" => "12.00",
          "Partner Share Currency" => "USD"
        }
      ]
    }
    body = AppStoreDigestSync.issue_body(
      kind: "monthly",
      digest_period: { key: "2026-07", label: "2026-07-01 through 2026-07-31" },
      analytics: analytics,
      adoption: adoption,
      sales: sales,
      finance: finance,
      summaries: [],
      run_url: "https://github.com/example/repo/actions/runs/1"
    )

    assert_includes body, "Impression"
    assert_includes body, "Average session duration"
    assert_includes body, "20 seconds"
    assert_includes body, "Net units"
    assert_includes body, "12 USD"
    assert_includes body, "Financial data"
    assert_includes body, "Source data"
    refute_includes body, "TestFlight adoption"
  end

  def test_filters_sales_report_to_the_requested_app
    content = <<~TSV
      Apple Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds
      6800438206\t3\t0.70\tUSD
      1234567890\t9\t0.70\tUSD
    TSV
    sales = AppStoreDigestSync.fetch_sales(
      app_id: "6800438206",
      vendor_number: "12345",
      frequency: "WEEKLY",
      token: "token",
      output_dir: "",
      download: ->(_url, token:) { content }
    )

    assert_equal 1, sales["rows"].length
    assert_equal "3", sales["rows"].first["Units"]
  end

  def test_periods_use_the_last_complete_week_and_month
    weekly = AppStoreDigestSync.period("weekly", Date.new(2026, 8, 13))
    monthly = AppStoreDigestSync.period("monthly", Date.new(2026, 8, 13))

    assert_equal "2026-W32", weekly[:key]
    assert_equal "2026-08-03 through 2026-08-09", weekly[:label]
    assert_equal "2026-07", monthly[:key]
    assert_equal "2026-07-01 through 2026-07-31", monthly[:label]
  end

  private

  def build
    {
      "type" => "builds",
      "id" => "build-1",
      "attributes" => { "version" => "42", "uploadedDate" => "2026-08-13T10:00:00Z" }
    }
  end

  def analytics_report
    {
      "type" => "analyticsReports",
      "id" => "report-1",
      "attributes" => {
        "name" => "App Store Discovery and Engagement Standard",
        "category" => "APP_STORE_ENGAGEMENT"
      }
    }
  end

  def analytics_instance(id, date)
    {
      "type" => "analyticsReportInstances",
      "id" => id,
      "attributes" => { "granularity" => "WEEKLY", "processingDate" => date }
    }
  end

  def analytics_segment
    {
      "type" => "analyticsReportSegments",
      "id" => "segment-1",
      "attributes" => { "url" => "https://example.test/report.tsv.gz" }
    }
  end
end
