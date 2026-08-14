# frozen_string_literal: true

require "cgi/escape"
require "csv"
require "date"
require "fileutils"
require "json"
require "uri"
require_relative "app_store_connect_support"

module AppStoreDigestSync
  API_ORIGIN = AppStoreConnectSupport::API_ORIGIN
  LABEL = "app-store-digest"
  MARKER_NAME = "app-store-digest-id"
  ANALYTICS_CATEGORIES = %w[APP_STORE_ENGAGEMENT COMMERCE APP_USAGE].freeze

  module_function

  def fetch_builds(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    AppStoreConnectSupport.paginated_data(
      "#{API_ORIGIN}/v1/apps/#{app_id}/builds?limit=200",
      token,
      get: get
    )
  end

  def fetch_testflight_adoption(builds:, token:, get: AppStoreConnectSupport.method(:get_json))
    builds.filter_map do |build|
      response = begin
        get.call("#{API_ORIGIN}/v1/builds/#{build.fetch("id")}/metrics/betaBuildUsages", token)
      rescue AppStoreConnectSupport::RequestError => error
        raise unless error.status == 404

        next
      end
      values = Array(response["data"]).flat_map { |group| Array(group["dataPoints"]) }.each_with_object({}) do |point, sums|
        point.fetch("values", {}).each { |key, value| sums[key] = sums.fetch(key, 0) + value.to_i }
      end
      { "build" => build, "values" => values, "raw" => response }
    end
  end

  def fetch_review_summaries(app_id:, platform:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form(
      "limit" => 200,
      "filter[platform]" => platform,
      "include" => "territory"
    )
    AppStoreConnectSupport.paginated_data(
      "#{API_ORIGIN}/v1/apps/#{app_id}/customerReviewSummarizations?#{query}",
      token,
      get: get
    )
  rescue AppStoreConnectSupport::RequestError => error
    raise unless error.status == 404

    []
  end

  def ensure_analytics_request(app_id:, token:, get:, post:)
    query = URI.encode_www_form("limit" => 200, "filter[accessType]" => "ONGOING")
    requests = AppStoreConnectSupport.paginated_data(
      "#{API_ORIGIN}/v1/apps/#{app_id}/analyticsReportRequests?#{query}",
      token,
      get: get
    )
    active = requests.find { |request| !request.dig("attributes", "stoppedDueToInactivity") }
    return [active, false] if active

    payload = {
      "data" => {
        "type" => "analyticsReportRequests",
        "attributes" => { "accessType" => "ONGOING" },
        "relationships" => { "app" => { "data" => { "type" => "apps", "id" => app_id } } }
      }
    }
    [post.call("#{API_ORIGIN}/v1/analyticsReportRequests", token, payload).fetch("data"), true]
  end

  def fetch_analytics(app_id:, granularity:, token:, output_dir:, get: AppStoreConnectSupport.method(:get_json),
                      post: AppStoreConnectSupport.method(:post_json), download: AppStoreConnectSupport.method(:get_bytes))
    request, created = ensure_analytics_request(app_id: app_id, token: token, get: get, post: post)
    reports = AppStoreConnectSupport.paginated_data(
      "#{API_ORIGIN}/v1/analyticsReportRequests/#{request.fetch("id")}/reports?limit=200",
      token,
      get: get
    ).select { |report| ANALYTICS_CATEGORIES.include?(report.dig("attributes", "category")) }

    results = reports.filter_map do |report|
      instances_query = URI.encode_www_form("limit" => 200, "filter[granularity]" => granularity)
      instances = AppStoreConnectSupport.paginated_data(
        "#{API_ORIGIN}/v1/analyticsReports/#{report.fetch("id")}/instances?#{instances_query}",
        token,
        get: get
      )
      latest_date = instances.filter_map { |instance| instance.dig("attributes", "processingDate") }.max
      next unless latest_date

      latest_instances = instances.select { |instance| instance.dig("attributes", "processingDate") == latest_date }
      contents = latest_instances.flat_map do |instance|
        segments = AppStoreConnectSupport.paginated_data(
          "#{API_ORIGIN}/v1/analyticsReportInstances/#{instance.fetch("id")}/segments?limit=200",
          token,
          get: get
        )
        segments.map.with_index do |segment, index|
          content = AppStoreConnectSupport.gunzip(download.call(segment.dig("attributes", "url"), token: nil))
          write_report_file(
            output_dir,
            "analytics-#{report.dig("attributes", "name")}-#{latest_date}-#{index + 1}.tsv",
            content
          )
          content
        end
      end
      rows = contents.flat_map { |content| parse_tsv(content) }
      {
        "name" => report.dig("attributes", "name"),
        "category" => report.dig("attributes", "category"),
        "processingDate" => latest_date,
        "rows" => rows,
        "segmentCount" => contents.length
      }
    end
    status = if results.empty?
               created ? "Report request created; Apple needs 24–48 hours to generate data." :
                 "Report request is active; Apple has not generated data yet."
             else
               "Available"
             end
    { "status" => status, "reports" => results }
  rescue AppStoreConnectSupport::RequestError => error
    raise unless [403, 404].include?(error.status)

    { "status" => "Unavailable to the current API key (Admin, Sales and Reports, or Finance access is required).", "reports" => [] }
  end

  def fetch_sales(app_id:, vendor_number:, frequency:, report_date:, token:, output_dir:,
                  download: AppStoreConnectSupport.method(:get_gzip_report))
    return { "status" => "Not configured: set the APP_STORE_CONNECT_VENDOR_NUMBER repository variable.", "rows" => [] } if vendor_number.empty?

    query = URI.encode_www_form(
      "filter[vendorNumber]" => vendor_number,
      "filter[reportType]" => "SALES",
      "filter[reportSubType]" => "SUMMARY",
      "filter[frequency]" => frequency,
      "filter[reportDate]" => report_date
    )
    content = AppStoreConnectSupport.gunzip(download.call("#{API_ORIGIN}/v1/salesReports?#{query}", token: token))
    write_report_file(output_dir, "sales-#{frequency.downcase}.tsv", content)
    rows = filter_app_rows(parse_tsv(content), app_id)
    { "status" => "Available", "rows" => rows }
  rescue AppStoreConnectSupport::RequestError => error
    raise unless [403, 404].include?(error.status)

    message = error.status == 403 ? "Unavailable to the current API key (Sales and Reports access is required)." : "No report is available for this period."
    { "status" => message, "rows" => [] }
  end

  def fetch_finance(app_id:, vendor_number:, today:, token:, output_dir:,
                    download: AppStoreConnectSupport.method(:get_gzip_report))
    return { "status" => "Not configured: set the APP_STORE_CONNECT_VENDOR_NUMBER repository variable.", "rows" => [] } if vendor_number.empty?

    report_months(today).each do |month|
      query = URI.encode_www_form(
        "filter[vendorNumber]" => vendor_number,
        "filter[reportType]" => "FINANCIAL",
        "filter[regionCode]" => "ZZ",
        "filter[reportDate]" => month
      )
      begin
        content = AppStoreConnectSupport.gunzip(
          download.call("#{API_ORIGIN}/v1/financeReports?#{query}", token: token)
        )
      rescue AppStoreConnectSupport::RequestError => error
        raise if error.status == 403
        raise unless [400, 404].include?(error.status)

        next
      end
      write_report_file(output_dir, "finance-#{month}.tsv", content)
      return { "status" => "Available for Apple fiscal month #{month}", "month" => month, "rows" => filter_app_rows(parse_tsv(content), app_id) }
    end
    { "status" => "No consolidated financial report is available for the latest fiscal months.", "rows" => [] }
  rescue AppStoreConnectSupport::RequestError => error
    raise unless error.status == 403

    { "status" => "Unavailable to the current API key (Account Holder, Admin, or Finance access is required).", "rows" => [] }
  end

  def report_months(today)
    first = Date.new(today.year, today.month, 1)
    (1..4).map { |offset| (first << offset).strftime("%Y-%m") }
  end

  def parse_tsv(content)
    text = content.encode("UTF-8", invalid: :replace, undef: :replace).delete_prefix("\uFEFF")
    CSV.parse(text, headers: true, col_sep: "\t", liberal_parsing: true).map(&:to_h)
  end

  def filter_app_rows(rows, app_id)
    identifier = %w[Apple\ Identifier App\ Apple\ ID App\ Apple\ Identifier].find do |field|
      rows.any? { |row| row.key?(field) }
    end
    return rows unless identifier

    rows.select { |row| row[identifier].to_s == app_id.to_s }
  end

  def write_report_file(output_dir, name, content)
    return if output_dir.to_s.empty?

    FileUtils.mkdir_p(output_dir)
    safe_name = name.gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-+/, "-")
    File.binwrite(File.join(output_dir, safe_name), content)
  end

  def analytics_metrics(reports)
    preferred_analytics_reports(reports).flat_map do |report|
      name = report.fetch("name")
      rows = report.fetch("rows")
      case name
      when /Discovery and Engagement/i
        grouped_metric_rows(name, rows, "Event", "Counts")
      when /Downloads/i
        grouped_metric_rows(name, rows, "Download Type", "Counts")
      when /Installations and Deletions/i
        grouped_metric_rows(name, rows, "Event", "Counts")
      when /Sessions/i
        sessions = sum_column(rows, "Sessions")
        duration = sum_column(rows, "Total Session Duration")
        values = [["Sessions", format_number(sessions)]]
        values << ["Average session duration", "#{format_number(duration / sessions)} seconds"] if sessions.positive?
        values.map { |metric, value| [name, metric, value] }
      when /Crashes/i
        [[name, "Crashes", sum_column(rows, "Crashes")]]
      else
        []
      end
    end
  end

  def preferred_analytics_reports(reports)
    reports.group_by { |report| report.fetch("name").sub(/\s+(Detailed|Standard)\z/i, "") }.values.map do |versions|
      versions.find { |report| report.fetch("name").match?(/Standard\z/i) } || versions.first
    end
  end

  def grouped_metric_rows(report_name, rows, dimension, measure)
    grouped = rows.each_with_object(Hash.new(0.0)) do |row, totals|
      key = row[dimension].to_s.strip
      next if key.empty?

      totals[key] += number(row[measure])
    end
    grouped.sort_by { |_, value| -value }.map { |key, value| [report_name, key, format_number(value)] }
  end

  def sum_column(rows, column)
    rows.sum { |row| number(row[column]) }
  end

  def number(value)
    Float(value.to_s.delete(","))
  rescue ArgumentError, TypeError
    0.0
  end

  def format_number(value)
    return value.to_i.to_s if value.to_f == value.to_i

    format("%.2f", value)
  end

  def analytics_section(analytics)
    metrics = analytics_metrics(analytics.fetch("reports"))
    metrics_table = if metrics.empty?
                      "No summarized metrics are available yet."
                    else
                      rows = metrics.map { |report, metric, value| "| #{table_value(report)} | #{table_value(metric)} | #{table_value(value)} |" }
                      (["| Report | Metric | Value |", "| --- | --- | ---: |"] + rows).join("\n")
                    end
    inventory = analytics.fetch("reports").map do |report|
      "| #{table_value(report["name"])} | #{table_value(report["category"])} | #{report["processingDate"]} | #{report["rows"].length} | #{report["segmentCount"]} |"
    end
    inventory_table = if inventory.empty?
                        "No report files are available yet."
                      else
                        (["| Report | Category | Processing date | Rows | Segments |", "| --- | --- | --- | ---: | ---: |"] + inventory).join("\n")
                      end
    <<~MARKDOWN.chomp
      Status: #{analytics.fetch("status")}

      #{metrics_table}

      <details>
      <summary>Downloaded report inventory</summary>

      #{inventory_table}
      </details>
    MARKDOWN
  end

  def adoption_section(adoption)
    return "No TestFlight build metrics are available." if adoption.empty?

    rows = adoption.sort_by { |item| item.dig("build", "attributes", "uploadedDate").to_s }.reverse.first(25).map do |item|
      attributes = item.fetch("build").fetch("attributes", {})
      values = item.fetch("values")
      "| #{table_value(attributes["version"])} | #{table_value(attributes["uploadedDate"])} | " \
        "#{values.fetch("inviteCount", 0)} | #{values.fetch("installCount", 0)} | " \
        "#{values.fetch("sessionCount", 0)} | #{values.fetch("crashCount", 0)} | #{values.fetch("feedbackCount", 0)} |"
    end
    (["| Build | Uploaded | Invites | Installs | Sessions | Crashes | Feedback |", "| --- | --- | ---: | ---: | ---: | ---: | ---: |"] + rows).join("\n")
  end

  def sales_section(sales)
    rows = sales.fetch("rows")
    return "Status: #{sales.fetch("status")}" if rows.empty?

    units = rows.sum { |row| row["Units"].to_i }
    refunds = rows.select { |row| row["Units"].to_i.negative? }.sum { |row| row["Units"].to_i.abs }
    proceeds = rows.each_with_object(Hash.new(0.0)) do |row, totals|
      currency = row["Currency of Proceeds"].to_s
      totals[currency] += row["Units"].to_i * number(row["Developer Proceeds"])
    end
    proceeds_text = proceeds.sort.map { |currency, value| "#{format_number(value)} #{currency}" }.join(", ")
    <<~MARKDOWN.chomp
      Status: #{sales.fetch("status")}

      | Metric | Value |
      | --- | ---: |
      | Net units | #{units} |
      | Refunded units | #{refunds} |
      | Estimated proceeds | #{table_value(proceeds_text.empty? ? "0" : proceeds_text)} |
    MARKDOWN
  end

  def finance_section(finance)
    rows = finance.fetch("rows")
    return "Status: #{finance.fetch("status")}" if rows.empty?

    quantity = rows.sum { |row| row["Quantity"].to_i }
    returns = rows.select { |row| row["Sale or Return"] == "R" }.sum { |row| row["Quantity"].to_i.abs }
    proceeds = rows.each_with_object(Hash.new(0.0)) do |row, totals|
      totals[row["Partner Share Currency"].to_s] += number(row["Extended Partner Share"])
    end
    proceeds_text = proceeds.sort.map { |currency, value| "#{format_number(value)} #{currency}" }.join(", ")
    <<~MARKDOWN.chomp
      Status: #{finance.fetch("status")}

      | Metric | Value |
      | --- | ---: |
      | Net quantity | #{quantity} |
      | Returns | #{returns} |
      | Final proceeds | #{table_value(proceeds_text.empty? ? "0" : proceeds_text)} |
    MARKDOWN
  end

  def review_summary_section(summaries)
    return "Apple has not generated a customer review summary for this app yet." if summaries.empty?

    summaries.map do |summary|
      attributes = summary.fetch("attributes", {})
      territory = summary.dig("relationships", "territory", "data", "id") || "All territories"
      "### #{table_value(territory)} · #{table_value(attributes["locale"])}\n\n#{attributes["text"]}\n\nGenerated #{attributes["createdDate"]}"
    end.join("\n\n")
  end

  def table_value(value)
    CGI.escapeHTML(value.to_s).gsub("|", "&#124;").gsub("\n", "<br>")
  end

  def period(kind, today)
    if kind == "weekly"
      finish = today - today.wday
      start = finish - 6
      { key: start.strftime("%G-W%V"), label: "#{start} through #{finish}", report_date: finish.to_s }
    else
      finish = Date.new(today.year, today.month, 1) - 1
      start = Date.new(finish.year, finish.month, 1)
      { key: start.strftime("%Y-%m"), label: "#{start} through #{finish}", report_date: finish.to_s }
    end
  end

  def issue_body(kind:, digest_period:, analytics:, adoption:, sales:, finance:, summaries:, run_url:)
    identity = "#{kind}-#{digest_period.fetch(:key)}"
    sections = [
      "<!-- #{MARKER_NAME}:#{identity} -->",
      "Reporting period: **#{digest_period.fetch(:label)}**",
      "## Downloads, engagement, and app usage\n\n#{analytics_section(analytics)}"
    ]
    sections << "## TestFlight adoption\n\n#{adoption_section(adoption)}" if kind == "weekly"
    sections << "## Sales\n\n#{sales_section(sales)}"
    sections << "## Financial data\n\n#{finance_section(finance)}" if kind == "monthly"
    sections << "## Customer review summary\n\n#{review_summary_section(summaries)}"
    sections << <<~MARKDOWN.chomp
      ## Source data

      Downloaded Apple report files and raw TestFlight metric responses are retained as an artifact on the [GitHub Actions run](#{run_url}).

      _Synced automatically from App Store Connect._
    MARKDOWN
    sections.join("\n\n")
  end

  def sync(repository:, kind:, digest_period:, body:)
    AppStoreConnectSupport.ensure_label(
      repository,
      LABEL,
      "Weekly or monthly App Store Connect report",
      color: "0E8A16"
    )
    identity = "#{kind}-#{digest_period.fetch(:key)}"
    issue = AppStoreConnectSupport.existing_issues(repository, MARKER_NAME)[identity]
    title = "[App Store #{kind.capitalize} Digest · #{digest_period.fetch(:key)}] Luxel"
    issue_number, changed = AppStoreConnectSupport.upsert_issue(
      repository: repository,
      issue: issue,
      title: title,
      body: body,
      label: LABEL
    )
    action = issue.nil? ? "Created" : (changed ? "Updated" : "Unchanged")
    puts "#{action} #{kind} digest issue ##{issue_number}"
  end

  def run(today: Date.today)
    kind = AppStoreConnectSupport.required_env("APP_STORE_DIGEST_KIND")
    abort("APP_STORE_DIGEST_KIND must be weekly or monthly") unless %w[weekly monthly].include?(kind)

    token = AppStoreConnectSupport.token_from_env
    app_id = AppStoreConnectSupport.required_env("APP_STORE_CONNECT_APP_ID")
    repository = AppStoreConnectSupport.required_env("GITHUB_REPOSITORY")
    platform = ENV.fetch("APP_STORE_CONNECT_PLATFORM", "MAC_OS")
    vendor_number = ENV["APP_STORE_CONNECT_VENDOR_NUMBER"].to_s.strip
    output_dir = ENV["APP_STORE_REPORT_OUTPUT_DIR"].to_s
    granularity = kind.upcase
    digest_period = period(kind, today)
    builds = fetch_builds(app_id: app_id, token: token)

    adoption = kind == "weekly" ? fetch_testflight_adoption(builds: builds, token: token) : []
    analytics = fetch_analytics(
      app_id: app_id,
      granularity: granularity,
      token: token,
      output_dir: output_dir
    )
    sales = fetch_sales(
      app_id: app_id,
      vendor_number: vendor_number,
      frequency: granularity,
      report_date: digest_period.fetch(:report_date),
      token: token,
      output_dir: output_dir
    )
    finance = if kind == "monthly"
                fetch_finance(
                  app_id: app_id,
                  vendor_number: vendor_number,
                  today: today,
                  token: token,
                  output_dir: output_dir
                )
              else
                { "status" => "Not included in weekly digests.", "rows" => [] }
              end
    summaries = fetch_review_summaries(app_id: app_id, platform: platform, token: token)
    write_report_file(
      output_dir,
      "testflight-adoption.json",
      JSON.pretty_generate(adoption)
    ) unless adoption.empty?
    run_url = "#{ENV.fetch("GITHUB_SERVER_URL", "https://github.com")}/#{repository}/actions/runs/#{ENV.fetch("GITHUB_RUN_ID", "")}".delete_suffix("/")
    body = issue_body(
      kind: kind,
      digest_period: digest_period,
      analytics: analytics,
      adoption: adoption,
      sales: sales,
      finance: finance,
      summaries: summaries,
      run_url: run_url
    )
    sync(repository: repository, kind: kind, digest_period: digest_period, body: body)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    AppStoreDigestSync.run
  rescue AppStoreConnectSupport::RequestError => error
    abort(error.message)
  end
end
