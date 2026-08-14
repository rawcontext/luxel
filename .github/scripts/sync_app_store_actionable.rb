# frozen_string_literal: true

require "cgi/escape"
require "digest"
require "json"
require "uri"
require_relative "app_store_connect_support"

module AppStoreActionableSync
  API_ORIGIN = AppStoreConnectSupport::API_ORIGIN
  MARKER_NAME = "app-store-action-id"
  REJECTION_STATES = %w[INVALID_BINARY METADATA_REJECTED REJECTED].freeze
  LABELS = {
    "screenshotFeedback" => ["testflight-feedback", "Screenshot feedback from a TestFlight tester", "5319E7"],
    "performanceRegression" => ["app-store-performance", "Performance regression reported by Apple", "D93F0B"],
    "appStoreRejection" => ["app-store-rejection", "App Store or TestFlight review rejection", "B60205"],
    "testflightRejection" => ["app-store-rejection", "App Store or TestFlight review rejection", "B60205"],
    "failedUpload" => ["app-store-upload", "Failed App Store Connect build upload", "B60205"]
  }.freeze

  module_function

  def fetch_screenshot_feedback(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form("limit" => 200, "sort" => "-createdDate", "include" => "build,tester")
    next_url = "#{API_ORIGIN}/v1/apps/#{app_id}/betaFeedbackScreenshotSubmissions?#{query}"
    records = []

    while next_url
      page = get.call(next_url, token)
      included = Array(page["included"]).to_h { |item| [[item["type"], item["id"]], item] }
      Array(page["data"]).each do |submission|
        build_id = submission.dig("relationships", "build", "data", "id")
        tester_id = submission.dig("relationships", "tester", "data", "id")
        records << {
          "kind" => "screenshotFeedback",
          "submission" => submission,
          "build" => included[["builds", build_id]],
          "tester" => included[["betaTesters", tester_id]]
        }
      end
      next_url = page.dig("links", "next")
    end

    records
  end

  def fetch_performance_regressions(app_id:, token:, get: AppStoreConnectSupport.method(:get_xcode_metrics_json))
    response = optional_get("#{API_ORIGIN}/v1/apps/#{app_id}/perfPowerMetrics", token, get)
    return [] unless response

    Array(response.dig("insights", "regressions")).map do |insight|
      {
        "kind" => "performanceRegression",
        "insight" => insight,
        "metricData" => matching_metric_data(response, insight)
      }
    end
  end

  def matching_metric_data(response, insight)
    Array(response["productData"]).filter_map do |product|
      categories = Array(product["metricCategories"]).select do |category|
        category["identifier"] == insight["metricCategory"]
      end
      metrics = categories.flat_map { |category| Array(category["metrics"]) }.select do |metric|
        metric["identifier"] == insight["metric"]
      end
      next if metrics.empty?

      { "platform" => product["platform"], "metrics" => metrics }
    end
  end

  def fetch_failed_uploads(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form(
      "limit" => 200,
      "sort" => "-uploadedDate",
      "filter[state]" => "FAILED",
      "include" => "build"
    )
    next_url = "#{API_ORIGIN}/v1/apps/#{app_id}/buildUploads?#{query}"
    records = []

    while next_url
      page = get.call(next_url, token)
      builds = Array(page["included"]).select { |item| item["type"] == "builds" }.to_h do |item|
        [item["id"], item]
      end
      Array(page["data"]).each do |upload|
        build_id = upload.dig("relationships", "build", "data", "id")
        records << { "kind" => "failedUpload", "upload" => upload, "build" => builds[build_id] }
      end
      next_url = page.dig("links", "next")
    end

    records
  rescue AppStoreConnectSupport::RequestError => error
    raise unless error.status == 404

    []
  end

  def fetch_app_store_rejections(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form(
      "limit" => 200,
      "filter[appVersionState]" => REJECTION_STATES.join(","),
      "include" => "build"
    )
    next_url = "#{API_ORIGIN}/v1/apps/#{app_id}/appStoreVersions?#{query}"
    records = []

    while next_url
      page = get.call(next_url, token)
      builds = Array(page["included"]).select { |item| item["type"] == "builds" }.to_h do |item|
        [item["id"], item]
      end
      Array(page["data"]).each do |version|
        build_id = version.dig("relationships", "build", "data", "id")
        records << {
          "kind" => "appStoreRejection",
          "version" => version,
          "build" => builds[build_id]
        }
      end
      next_url = page.dig("links", "next")
    end

    records
  end

  def fetch_testflight_rejections(builds:, token:, get: AppStoreConnectSupport.method(:get_json))
    builds.each_slice(50).flat_map do |batch|
      query = URI.encode_www_form(
        "limit" => 200,
        "filter[build]" => batch.map { |build| build.fetch("id") }.join(","),
        "filter[betaReviewState]" => "REJECTED",
        "include" => "build"
      )
      next_url = "#{API_ORIGIN}/v1/betaAppReviewSubmissions?#{query}"
      records = []

      while next_url
        page = get.call(next_url, token)
        included = Array(page["included"]).select { |item| item["type"] == "builds" }.to_h do |item|
          [item["id"], item]
        end
        Array(page["data"]).each do |submission|
          build_id = submission.dig("relationships", "build", "data", "id")
          records << {
            "kind" => "testflightRejection",
            "submission" => submission,
            "build" => included[build_id] || batch.find { |build| build["id"] == build_id }
          }
        end
        next_url = page.dig("links", "next")
      end

      records
    end
  end

  def fetch_builds(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    AppStoreConnectSupport.paginated_data(
      "#{API_ORIGIN}/v1/apps/#{app_id}/builds?limit=200",
      token,
      get: get
    )
  end

  def optional_get(url, token, get)
    get.call(url, token)
  rescue AppStoreConnectSupport::RequestError => error
    raise unless error.status == 404

    nil
  end

  def entry(record)
    raw = JSON.pretty_generate(record)
    sha256, chunk_count = AppStoreConnectSupport.raw_data_metadata(raw)
    result = case record.fetch("kind")
             when "screenshotFeedback" then screenshot_entry(record)
             when "performanceRegression" then performance_entry(record)
             when "failedUpload" then failed_upload_entry(record)
             when "appStoreRejection" then app_store_rejection_entry(record)
             when "testflightRejection" then testflight_rejection_entry(record)
             end
    result.merge(
      raw: raw,
      body: "#{result.fetch(:body)}\n\n#{raw_data_note(sha256, chunk_count)}\n\n" \
        "#{AppStoreConnectSupport.raw_data_marker(sha256)}\n\n_Synced automatically from App Store Connect._\n"
    )
  end

  def screenshot_entry(record)
    submission = record.fetch("submission")
    attributes = submission.fetch("attributes")
    identity = "testflight-screenshot-#{submission.fetch("id")}"
    platform = attributes["appPlatform"] || attributes["devicePlatform"] || "Unknown platform"
    body = <<~MARKDOWN.chomp
      <!-- #{MARKER_NAME}:#{identity} -->

      ## Tester comment

      #{code_block(attributes["comment"].to_s.empty? ? "(No tester comment.)" : attributes["comment"])}

      ## Screenshots

      #{screenshots_section(attributes["screenshots"])}

      ## Submission details

      #{attribute_table(attributes.reject { |key, _| %w[comment screenshots].include?(key) })}

      ## Build

      #{resource_section(record["build"])}

      ## Tester

      #{resource_section(record["tester"])}

      Submission ID: `#{submission.fetch("id")}`
    MARKDOWN
    {
      identity: identity,
      title: clean_title(
        "[TestFlight Feedback · #{platform} · #{attributes["osVersion"]}] #{attributes["deviceModel"]}"
      ),
      body: body,
      label: LABELS.fetch("screenshotFeedback")
    }
  end

  def performance_entry(record)
    insight = record.fetch("insight")
    identity_source = [
      insight["latestVersion"], insight["metricCategory"], insight["metric"], insight["subSystemLabel"]
    ].join("|")
    identity = "performance-regression-#{Digest::SHA256.hexdigest(identity_source)[0, 20]}"
    impact = insight["highImpact"] ? "High impact" : "Regression"
    body = <<~MARKDOWN.chomp
      <!-- #{MARKER_NAME}:#{identity} -->

      ## Apple performance insight

      #{insight["summaryString"]}

      | Field | Value |
      | --- | --- |
      | Impact | #{impact} |
      | Metric category | #{table_value(insight["metricCategory"])} |
      | Metric | #{table_value(insight["metric"])} |
      | Latest version | #{table_value(insight["latestVersion"])} |
      | Reference versions | #{table_value(insight["referenceVersions"])} |
      | Maximum latest-version value | #{table_value(insight["maxLatestVersionValue"])} |
      | Subsystem | #{table_value(insight["subSystemLabel"])} |

      ## Affected populations

      #{populations_table(insight["populations"])}
    MARKDOWN
    {
      identity: identity,
      title: clean_title(
        "[App Store Performance · #{impact} · #{insight["latestVersion"]}] " \
        "#{insight["metricCategory"]} #{insight["metric"]}"
      ),
      body: body,
      label: LABELS.fetch("performanceRegression")
    }
  end

  def failed_upload_entry(record)
    upload = record.fetch("upload")
    attributes = upload.fetch("attributes")
    state = attributes.fetch("state", {})
    identity = "failed-upload-#{upload.fetch("id")}"
    version = attributes["cfBundleShortVersionString"]
    build_number = attributes["cfBundleVersion"]
    body = <<~MARKDOWN.chomp
      <!-- #{MARKER_NAME}:#{identity} -->

      ## Upload failure

      #{state_details_section(state)}

      ## Upload details

      #{attribute_table(attributes.reject { |key, _| key == "state" })}

      ## Build

      #{resource_section(record["build"])}

      Upload ID: `#{upload.fetch("id")}`
    MARKDOWN
    {
      identity: identity,
      title: clean_title("[App Store Upload Failed · #{version} (#{build_number})] #{attributes["platform"]}"),
      body: body,
      label: LABELS.fetch("failedUpload")
    }
  end

  def app_store_rejection_entry(record)
    version = record.fetch("version")
    attributes = version.fetch("attributes")
    state = attributes["appVersionState"] || attributes["appStoreState"]
    identity = "app-store-rejection-#{version.fetch("id")}"
    body = <<~MARKDOWN.chomp
      <!-- #{MARKER_NAME}:#{identity} -->

      ## App Store rejection

      #{attribute_table(attributes)}

      ## Build

      #{resource_section(record["build"])}

      App Store version ID: `#{version.fetch("id")}`
    MARKDOWN
    {
      identity: identity,
      title: clean_title(
        "[App Store Rejection · #{state} · #{attributes["platform"]}] #{attributes["versionString"]}"
      ),
      body: body,
      label: LABELS.fetch("appStoreRejection")
    }
  end

  def testflight_rejection_entry(record)
    submission = record.fetch("submission")
    attributes = submission.fetch("attributes")
    build = record["build"]
    build_number = build&.dig("attributes", "version") || "Unknown build"
    identity = "testflight-rejection-#{submission.fetch("id")}"
    body = <<~MARKDOWN.chomp
      <!-- #{MARKER_NAME}:#{identity} -->

      ## TestFlight review rejection

      #{attribute_table(attributes)}

      ## Build

      #{resource_section(build)}

      Beta review submission ID: `#{submission.fetch("id")}`
    MARKDOWN
    {
      identity: identity,
      title: clean_title("[TestFlight Rejection · build #{build_number}] #{attributes["betaReviewState"]}"),
      body: body,
      label: LABELS.fetch("testflightRejection")
    }
  end

  def screenshots_section(screenshots)
    values = Array(screenshots)
    return "No screenshot was provided by App Store Connect." if values.empty?

    values.each_with_index.map do |screenshot, index|
      <<~MARKDOWN.chomp
        ### Screenshot #{index + 1}

        ![TestFlight feedback screenshot #{index + 1}](#{screenshot["url"]})

        #{screenshot["width"]} × #{screenshot["height"]} pixels · URL expires #{screenshot["expirationDate"]}
      MARKDOWN
    end.join("\n\n")
  end

  def populations_table(populations)
    rows = Array(populations).map do |population|
      "| #{table_value(population["device"])} | #{table_value(population["percentile"])} | " \
        "#{table_value(population["latestVersionValue"])} | #{table_value(population["referenceAverageValue"])} | " \
        "#{table_value(population["deltaPercentage"])}% | #{table_value(population["summaryString"])} |"
    end
    return "Apple did not provide population details." if rows.empty?

    (["| Device | Percentile | Latest | Reference average | Change | Summary |", "| --- | --- | ---: | ---: | ---: | --- |"] + rows).join("\n")
  end

  def state_details_section(state)
    %w[errors warnings infos].map do |kind|
      values = Array(state[kind])
      next if values.empty?

      heading = kind.capitalize
      lines = values.map { |value| "- `#{value["code"]}` — #{value["description"]}" }
      "### #{heading}\n\n#{lines.join("\n")}"
    end.compact.join("\n\n").then do |value|
      value.empty? ? "State: `#{state["state"]}` (Apple provided no detail records.)" : value
    end
  end

  def clean_title(value)
    value.to_s.gsub(/\s+/, " ").strip.slice(0, 256)
  end

  def code_block(value)
    value.to_s.lines(chomp: true).map { |line| "    #{line}" }.join("\n")
  end

  def attribute_table(attributes)
    rows = attributes.sort.map { |key, value| "| #{humanize(key)} | #{table_value(value)} |" }
    (["| Field | Value |", "| --- | --- |"] + rows).join("\n")
  end

  def resource_section(resource)
    return "Not provided by App Store Connect." unless resource

    "#{attribute_table(resource.fetch("attributes", {}))}\n\nResource ID: `#{resource.fetch("id")}`"
  end

  def humanize(value)
    value.gsub(/([a-z0-9])([A-Z])/, "\\1 \\2").split.map(&:capitalize).join(" ")
  end

  def table_value(value)
    display = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s
    CGI.escapeHTML(display).gsub("|", "&#124;").gsub("\n", "<br>")
  end

  def raw_data_note(sha256, chunk_count)
    <<~MARKDOWN.chomp
      ## Raw App Store Connect data

      The complete raw record is stored below in #{chunk_count} issue #{chunk_count == 1 ? "comment" : "comments"}.

      SHA-256: `#{sha256}`
    MARKDOWN
  end

  def sync(repository:, records:)
    LABELS.values.uniq.each do |name, description, color|
      AppStoreConnectSupport.ensure_label(repository, name, description, color: color)
    end
    issues = AppStoreConnectSupport.existing_issues(repository, MARKER_NAME)

    records.each do |record|
      item = entry(record)
      issue = issues[item.fetch(:identity)]
      issue_number, changed = AppStoreConnectSupport.upsert_issue(
        repository: repository,
        issue: issue,
        title: item.fetch(:title),
        body: item.fetch(:body),
        label: item.fetch(:label).first
      )
      AppStoreConnectSupport.sync_raw_data_comments(
        repository: repository,
        issue_number: issue_number,
        identity: item.fetch(:identity),
        value: item.fetch(:raw)
      )

      if issue.nil?
        puts "Created issue ##{issue_number} for #{item.fetch(:identity)}"
      elsif changed
        puts "Updated issue ##{issue_number} for #{item.fetch(:identity)}"
      end
    end
  end

  def run
    token = AppStoreConnectSupport.token_from_env
    app_id = AppStoreConnectSupport.required_env("APP_STORE_CONNECT_APP_ID")
    builds = fetch_builds(app_id: app_id, token: token)
    records = fetch_screenshot_feedback(app_id: app_id, token: token)
    records.concat(fetch_performance_regressions(app_id: app_id, token: token))
    records.concat(fetch_failed_uploads(app_id: app_id, token: token))
    records.concat(fetch_app_store_rejections(app_id: app_id, token: token))
    records.concat(fetch_testflight_rejections(builds: builds, token: token))
    counts = records.group_by { |record| record.fetch("kind") }.transform_values(&:length)
    puts "Found actionable App Store Connect records: #{counts}"
    sync(repository: AppStoreConnectSupport.required_env("GITHUB_REPOSITORY"), records: records)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    AppStoreActionableSync.run
  rescue AppStoreConnectSupport::RequestError => error
    abort(error.message)
  end
end
