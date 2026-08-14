# frozen_string_literal: true

require "cgi/escape"
require "json"
require "uri"
require_relative "app_store_connect_support"

module AppStoreCrashSync
  LABEL = "app-store-crash"
  MARKER_NAME = "app-store-crash-id"
  API_ORIGIN = AppStoreConnectSupport::API_ORIGIN

  module_function

  def fetch_builds(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form("limit" => 200)
    AppStoreConnectSupport.paginated_data(
      "#{API_ORIGIN}/v1/apps/#{app_id}/builds?#{query}",
      token,
      get: get
    )
  end

  def fetch_diagnostics(builds:, token:, get: AppStoreConnectSupport.method(:get_json))
    builds.flat_map do |build|
      query = URI.encode_www_form("limit" => 200)
      signatures = AppStoreConnectSupport.paginated_data(
        "#{API_ORIGIN}/v1/builds/#{build.fetch("id")}/diagnosticSignatures?#{query}",
        token,
        get: get
      )
      signatures.map do |signature|
        logs_url = "#{API_ORIGIN}/v1/diagnosticSignatures/#{signature.fetch("id")}/logs?limit=200"
        {
          "kind" => "diagnostic",
          "build" => build,
          "signature" => signature,
          "logs" => get.call(logs_url, token)
        }
      end
    end
  end

  def fetch_testflight_crashes(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form("limit" => 200, "sort" => "-createdDate", "include" => "build,tester")
    next_url = "#{API_ORIGIN}/v1/apps/#{app_id}/betaFeedbackCrashSubmissions?#{query}"
    crashes = []

    while next_url
      page = get.call(next_url, token)
      included = Array(page["included"]).to_h { |item| [[item["type"], item["id"]], item] }
      Array(page["data"]).each do |submission|
        build_id = submission.dig("relationships", "build", "data", "id")
        tester_id = submission.dig("relationships", "tester", "data", "id")
        log_url = "#{API_ORIGIN}/v1/betaFeedbackCrashSubmissions/#{submission.fetch("id")}/crashLog"
        crashes << {
          "kind" => "testflightCrash",
          "submission" => submission,
          "build" => included[["builds", build_id]],
          "tester" => included[["betaTesters", tester_id]],
          "crashLog" => get.call(log_url, token).fetch("data")
        }
      end
      next_url = page.dig("links", "next")
    end

    crashes
  end

  def entry(record)
    raw = JSON.pretty_generate(record)
    sha256, chunk_count = AppStoreConnectSupport.raw_data_metadata(raw)

    if record.fetch("kind") == "diagnostic"
      diagnostic_entry(record, raw, sha256, chunk_count)
    else
      testflight_entry(record, raw, sha256, chunk_count)
    end
  end

  def diagnostic_entry(record, raw, sha256, chunk_count)
    build = record.fetch("build")
    signature = record.fetch("signature")
    attributes = signature.fetch("attributes")
    build_attributes = build.fetch("attributes")
    identity = "diagnostic-#{build.fetch("id")}-#{signature.fetch("id")}"
    title = clean_title(
      "[App Store Diagnostic · #{attributes["diagnosticType"]} · build #{build_attributes["version"]}] " \
      "#{attributes["signature"]}"
    )
    body = <<~MARKDOWN
      <!-- #{MARKER_NAME}:#{identity} -->
      #{AppStoreConnectSupport.raw_data_marker(sha256)}

      ## Diagnostic signature

      #{code_block(attributes["signature"])}

      ## Signature details

      #{attribute_table(attributes.reject { |key, _| key == "signature" })}

      ## Build details

      #{attribute_table(build_attributes)}

      | Resource | ID |
      | --- | --- |
      | Build | `#{build.fetch("id")}` |
      | Diagnostic signature | `#{signature.fetch("id")}` |

      #{raw_data_note(sha256, chunk_count)}

      _Synced automatically from App Store Connect._
    MARKDOWN

    { identity: identity, title: title, body: body, raw: raw }
  end

  def testflight_entry(record, raw, sha256, chunk_count)
    submission = record.fetch("submission")
    attributes = submission.fetch("attributes")
    build = record["build"]
    tester = record["tester"]
    identity = "testflight-crash-#{submission.fetch("id")}"
    platform = attributes["appPlatform"] || attributes["devicePlatform"] || "Unknown platform"
    title = clean_title(
      "[TestFlight Crash · #{platform} · #{attributes["osVersion"]}] #{attributes["deviceModel"]}"
    )
    body = <<~MARKDOWN
      <!-- #{MARKER_NAME}:#{identity} -->
      #{AppStoreConnectSupport.raw_data_marker(sha256)}

      ## Tester comment

      #{code_block(attributes["comment"].to_s.empty? ? "(No tester comment.)" : attributes["comment"])}

      ## Crash submission

      #{attribute_table(attributes.reject { |key, _| key == "comment" })}

      ## Build

      #{resource_section(build)}

      ## Tester

      #{resource_section(tester)}

      | Resource | ID |
      | --- | --- |
      | Crash submission | `#{submission.fetch("id")}` |
      | Crash log | `#{record.fetch("crashLog").fetch("id")}` |

      #{raw_data_note(sha256, chunk_count)}

      _Synced automatically from App Store Connect._
    MARKDOWN

    { identity: identity, title: title, body: body, raw: raw }
  end

  def clean_title(value)
    value.to_s.gsub(/\s+/, " ").strip.slice(0, 256)
  end

  def code_block(value)
    value.to_s.lines(chomp: true).map { |line| "    #{line}" }.join("\n")
  end

  def attribute_table(attributes)
    rows = attributes.sort.map do |key, value|
      "| #{humanize(key)} | #{table_value(value)} |"
    end
    (["| Field | Value |", "| --- | --- |"] + rows).join("\n")
  end

  def resource_section(resource)
    return "Not provided by App Store Connect." unless resource

    <<~MARKDOWN.chomp
      #{attribute_table(resource.fetch("attributes", {}))}

      Resource ID: `#{resource.fetch("id")}`
    MARKDOWN
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
    AppStoreConnectSupport.ensure_label(
      repository,
      LABEL,
      "Crash or diagnostic data from App Store Connect"
    )
    issues = AppStoreConnectSupport.existing_issues(repository, MARKER_NAME)

    records.each do |record|
      item = entry(record)
      issue = issues[item.fetch(:identity)]
      issue_number, changed = AppStoreConnectSupport.upsert_issue(
        repository: repository,
        issue: issue,
        title: item.fetch(:title),
        body: item.fetch(:body),
        label: LABEL
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
    diagnostics = fetch_diagnostics(builds: builds, token: token)
    crashes = fetch_testflight_crashes(app_id: app_id, token: token)
    puts "Found #{diagnostics.length} build diagnostics and #{crashes.length} TestFlight crash submissions"
    sync(
      repository: AppStoreConnectSupport.required_env("GITHUB_REPOSITORY"),
      records: diagnostics + crashes
    )
  end
end

AppStoreCrashSync.run if $PROGRAM_NAME == __FILE__
