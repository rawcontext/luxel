# frozen_string_literal: true

require "cgi/escape"
require "json"
require "uri"
require_relative "app_store_connect_support"

module AppStoreReviewSync
  LABEL = "app-store-review"
  API_ORIGIN = AppStoreConnectSupport::API_ORIGIN

  module_function

  def fetch_reviews(app_id:, token:, get: AppStoreConnectSupport.method(:get_json))
    query = URI.encode_www_form(
      "limit" => 200,
      "sort" => "-createdDate",
      "include" => "response",
      "fields[customerReviewResponses]" => "responseBody,lastModifiedDate,state"
    )
    next_url = "#{API_ORIGIN}/v1/apps/#{app_id}/customerReviews?#{query}"
    reviews = []

    while next_url
      page = get.call(next_url, token)
      responses = Array(page["included"]).to_h { |item| [item["id"], item] }
      Array(page["data"]).each do |review|
        response_id = review.dig("relationships", "response", "data", "id")
        reviews << [review, responses[response_id]]
      end
      next_url = page.dig("links", "next")
    end

    reviews
  end

  def marker(review_id)
    "<!-- app-store-review-id:#{review_id} -->"
  end

  def issue_title(review)
    attributes = review.fetch("attributes")
    rating = attributes.fetch("rating")
    territory = attributes.fetch("territory")
    review_title = attributes["title"].to_s.strip
    review_title = "Review by #{attributes.fetch("reviewerNickname")}" if review_title.empty?
    title = "[App Store · #{rating}★ · #{territory}] #{review_title.gsub(/\s+/, " ")}"
    title.slice(0, 256)
  end

  def issue_body(review, response)
    attributes = review.fetch("attributes")
    review_text = attributes["body"].to_s
    response_attributes = response&.fetch("attributes", nil)

    <<~MARKDOWN
      #{marker(review.fetch("id"))}

      ## Review

      #{code_block(review_text.empty? ? "(No review text.)" : review_text)}

      ## Details

      | Field | Value |
      | --- | --- |
      | Rating | #{attributes.fetch("rating")} / 5 |
      | Title | #{table_value(attributes["title"])} |
      | Reviewer | #{table_value(attributes["reviewerNickname"])} |
      | Territory | #{table_value(attributes["territory"])} |
      | Submitted | #{table_value(attributes["createdDate"])} |
      | App Store review ID | `#{review.fetch("id")}` |

      ## Developer response

      #{response_section(response_attributes)}

      <details>
      <summary>Raw App Store Connect data</summary>

      <pre><code>#{CGI.escapeHTML(JSON.pretty_generate({ "review" => review, "response" => response }))}</code></pre>
      </details>

      _Synced automatically from App Store Connect._
    MARKDOWN
  end

  def code_block(value)
    value.lines(chomp: true).map { |line| "    #{line}" }.join("\n")
  end

  def table_value(value)
    CGI.escapeHTML(value.to_s).gsub("|", "&#124;").gsub("\n", "<br>")
  end

  def response_section(attributes)
    return "No developer response is associated with this review." unless attributes

    response = code_block(attributes["responseBody"].to_s)
    <<~MARKDOWN.chomp
      #{response}

      State: `#{attributes["state"]}`<br>
      Last modified: #{attributes["lastModifiedDate"]}
    MARKDOWN
  end

  def sync(repository:, reviews:)
    AppStoreConnectSupport.ensure_label(
      repository,
      LABEL,
      "Customer review from the App Store",
      color: "1D76DB"
    )
    issues = AppStoreConnectSupport.existing_issues(repository, "app-store-review-id")

    reviews.each do |review, response|
      title = issue_title(review)
      body = issue_body(review, response)
      issue = issues[review.fetch("id")]
      issue_number, changed = AppStoreConnectSupport.upsert_issue(
        repository: repository,
        issue: issue,
        title: title,
        body: body,
        label: LABEL
      )

      if issue.nil?
        puts "Created issue for App Store review #{review.fetch("id")}"
      elsif changed
        puts "Updated issue ##{issue_number} for App Store review #{review.fetch("id")}"
      end
    end
  end

  def run
    token = AppStoreConnectSupport.token_from_env
    reviews = fetch_reviews(
      app_id: AppStoreConnectSupport.required_env("APP_STORE_CONNECT_APP_ID"),
      token: token
    )
    puts "Found #{reviews.length} App Store reviews"
    sync(
      repository: AppStoreConnectSupport.required_env("GITHUB_REPOSITORY"),
      reviews: reviews
    )
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    AppStoreReviewSync.run
  rescue AppStoreConnectSupport::RequestError => error
    abort(error.message)
  end
end
