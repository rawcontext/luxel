# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "open3"
require "uri"

module AppStoreConnectSupport
  API_ORIGIN = "https://api.appstoreconnect.apple.com"

  class RequestError < StandardError
    attr_reader :status

    def initialize(status, body)
      @status = Integer(status)
      super("App Store Connect request failed (#{status}): #{body}")
    end
  end

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

  def token_from_env
    jwt(
      key_id: required_env("APP_STORE_CONNECT_API_KEY_ID"),
      issuer_id: required_env("APP_STORE_CONNECT_API_ISSUER_ID"),
      private_key: Base64.decode64(required_env("APP_STORE_CONNECT_API_KEY_BASE64"))
    )
  end

  def get_json(url, token)
    response = request(url, token: token, accept: "application/json")
    JSON.parse(response.body)
  end

  def get_xcode_metrics_json(url, token, request: method(:request))
    response = request.call(url, token: token, accept: "application/vnd.apple.xcode-metrics+json")
    JSON.parse(response.body)
  end

  def request(url, token:, accept:)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}" if token
    request["Accept"] = accept
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
    return response if response.is_a?(Net::HTTPSuccess)

    raise RequestError.new(response.code, response.body)
  end

  def paginated_data(url, token, get: method(:get_json))
    data = []
    next_url = url

    while next_url
      page = get.call(next_url, token)
      data.concat(Array(page["data"]))
      next_url = page.dig("links", "next")
    end

    data
  end

  def gh(*arguments, input: nil)
    stdout, stderr, status = Open3.capture3(
      { "GH_TOKEN" => required_env("GH_TOKEN") },
      "gh", *arguments,
      stdin_data: input.to_s
    )
    abort("gh #{arguments.join(" ")} failed: #{stderr}") unless status.success?

    stdout
  end

  def ensure_label(repository, name, description, color: "B60205")
    gh(
      "label", "create", name,
      "--repo", repository,
      "--color", color,
      "--description", description,
      "--force"
    )
  end

  def existing_issues(repository, marker_name)
    output = gh(
      "api", "--paginate", "--slurp",
      "repos/#{repository}/issues?state=all&per_page=100"
    )
    pattern = /<!-- #{Regexp.escape(marker_name)}:([^ ]+) -->/
    JSON.parse(output).flatten.filter_map do |issue|
      match = issue["body"].to_s.match(pattern)
      next unless match

      [match[1], issue]
    end.to_h
  end

  def upsert_issue(repository:, issue:, title:, body:, label:)
    if issue.nil?
      output = gh(
        "issue", "create",
        "--repo", repository,
        "--title", title,
        "--body-file", "-",
        "--label", label,
        input: body
      )
      return [Integer(output.strip.split("/").last), true]
    end

    changed = issue["title"] != title || issue["body"] != body ||
      Array(issue["labels"]).none? { |item| item["name"] == label }
    if changed
      gh(
        "issue", "edit", issue.fetch("number").to_s,
        "--repo", repository,
        "--title", title,
        "--body-file", "-",
        "--add-label", label,
        input: body
      )
    end

    [issue.fetch("number"), changed]
  end

  def raw_data_metadata(value)
    [Digest::SHA256.hexdigest(value), utf8_chunks(value).length]
  end

  def raw_data_marker(sha256)
    "<!-- app-store-raw-data-sha256:#{sha256} -->"
  end

  def sync_raw_data_comments(repository:, issue_number:, identity:, value:)
    chunks = utf8_chunks(value)
    key = Digest::SHA256.hexdigest(identity)[0, 20]
    comments = JSON.parse(
      gh(
        "api", "--paginate", "--slurp",
        "repos/#{repository}/issues/#{issue_number}/comments?per_page=100"
      )
    ).flatten
    existing = comments.filter_map do |comment|
      match = comment["body"].to_s.match(/<!-- app-store-raw-data:#{key}:(\d+) -->/)
      match ? [Integer(match[1]), comment] : nil
    end.to_h

    chunks.each_with_index do |chunk, index|
      position = index + 1
      body = raw_comment_body(key, position, chunks.length, chunk)
      comment = existing[position]
      next if comment && comment["body"] == body

      path = if comment
               "repos/#{repository}/issues/comments/#{comment.fetch("id")}"
             else
               "repos/#{repository}/issues/#{issue_number}/comments"
             end
      method = comment ? "PATCH" : "POST"
      gh("api", "--method", method, path, "--input", "-", input: JSON.generate(body: body))
    end

    existing.each do |position, comment|
      next if position <= chunks.length

      body = "<!-- app-store-raw-data:#{key}:#{position} -->\n\n_Superseded by newer App Store Connect data._"
      next if comment["body"] == body

      gh(
        "api", "--method", "PATCH",
        "repos/#{repository}/issues/comments/#{comment.fetch("id")}",
        "--input", "-",
        input: JSON.generate(body: body)
      )
    end
  end

  def utf8_chunks(value, maximum_bytes: 55_000)
    remaining = value.dup
    chunks = []
    until remaining.empty?
      length = [remaining.bytesize, maximum_bytes].min
      length -= 1 while length.positive? && continuation_byte?(remaining.getbyte(length))
      chunks << remaining.byteslice(0, length)
      remaining = remaining.byteslice(length..) || ""
    end
    chunks
  end

  def continuation_byte?(byte)
    byte && (byte & 0b1100_0000) == 0b1000_0000
  end

  def raw_comment_body(key, position, total, value)
    fence = "`" * [4, value.scan(/`+/).map(&:length).max.to_i + 1].max
    <<~MARKDOWN
      <!-- app-store-raw-data:#{key}:#{position} -->

      Raw App Store Connect data (#{position}/#{total}):

      #{fence}json
      #{value}
      #{fence}
    MARKDOWN
  end
end
