# frozen_string_literal: true

require "base64"
require "cgi"
require "json"
require "net/http"
require "openssl"
require "open3"
require "uri"

module AppStoreReviewSync
  LABEL = "app-store-review"
  API_ORIGIN = "https://api.appstoreconnect.apple.com"

  module_function

  def required_env(name)
    value = ENV[name].to_s.strip
    abort("Missing required environment variable #{name}") if value.empty?

    value
  end

  def base64url(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def jwt(key_id:, issuer_id:, private_key:, now: Time.now.to_i)
    header = base64url(JSON.generate(alg: "ES256", kid: key_id, typ: "JWT"))
    claims = base64url(JSON.generate(iss: issuer_id, iat: now, exp: now + 1_200, aud: "appstoreconnect-v1"))
    signing_input = "#{header}.#{claims}"
    key = OpenSSL::PKey.read(private_key)
    der_signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
    integers = OpenSSL::ASN1.decode(der_signature).value
    signature = integers.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join

    "#{signing_input}.#{base64url(signature)}"
  end

  def get_json(url, token)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    abort("App Store Connect request failed (#{response.code}): #{response.body}")
  end

  def fetch_reviews(app_id:, token:, get: method(:get_json))
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

  def gh(*arguments, input: nil)
    stdout, stderr, status = Open3.capture3({ "GH_TOKEN" => required_env("GH_TOKEN") }, "gh", *arguments, stdin_data: input.to_s)
    abort("gh #{arguments.join(" ")} failed: #{stderr}") unless status.success?

    stdout
  end

  def existing_issues(repository)
    output = gh(
      "api", "--paginate", "--slurp",
      "repos/#{repository}/issues?state=all&per_page=100"
    )
    JSON.parse(output).flatten.filter_map do |issue|
      match = issue["body"].to_s.match(/<!-- app-store-review-id:([^ ]+) -->/)
      next unless match

      [match[1], issue]
    end.to_h
  end

  def sync(repository:, reviews:)
    gh("label", "create", LABEL, "--repo", repository, "--color", "1D76DB", "--description", "Customer review from the App Store", "--force")
    issues = existing_issues(repository)

    reviews.each do |review, response|
      title = issue_title(review)
      body = issue_body(review, response)
      issue = issues[review.fetch("id")]

      if issue.nil?
        gh("issue", "create", "--repo", repository, "--title", title, "--body-file", "-", "--label", LABEL, input: body)
        puts "Created issue for App Store review #{review.fetch("id")}"
      elsif issue["title"] != title || issue["body"] != body || Array(issue["labels"]).none? { |label| label["name"] == LABEL }
        gh("issue", "edit", issue.fetch("number").to_s, "--repo", repository, "--title", title, "--body-file", "-", "--add-label", LABEL, input: body)
        puts "Updated issue ##{issue.fetch("number")} for App Store review #{review.fetch("id")}"
      end
    end
  end

  def run
    token = jwt(
      key_id: required_env("APP_STORE_CONNECT_API_KEY_ID"),
      issuer_id: required_env("APP_STORE_CONNECT_API_ISSUER_ID"),
      private_key: Base64.decode64(required_env("APP_STORE_CONNECT_API_KEY_BASE64"))
    )
    reviews = fetch_reviews(app_id: required_env("APP_STORE_CONNECT_APP_ID"), token: token)
    puts "Found #{reviews.length} App Store reviews"
    sync(repository: required_env("GITHUB_REPOSITORY"), reviews: reviews)
  end
end

AppStoreReviewSync.run if $PROGRAM_NAME == __FILE__
