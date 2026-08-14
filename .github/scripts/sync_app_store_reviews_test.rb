# frozen_string_literal: true

require "minitest/autorun"
require "openssl"
require_relative "sync_app_store_reviews"

class AppStoreReviewSyncTest < Minitest::Test
  def test_jwt_has_valid_es256_signature_and_expected_claims
    key = OpenSSL::PKey::EC.generate("prime256v1")
    token = AppStoreReviewSync.jwt(
      key_id: "KEY123",
      issuer_id: "issuer-123",
      private_key: key.to_pem,
      now: 1_700_000_000
    )
    encoded_header, encoded_claims, encoded_signature = token.split(".")
    header = decode_json(encoded_header)
    claims = decode_json(encoded_claims)

    assert_equal({ "alg" => "ES256", "kid" => "KEY123", "typ" => "JWT" }, header)
    assert_equal "issuer-123", claims["iss"]
    assert_equal 1_700_001_200, claims["exp"]
    assert key.dsa_verify_asn1(
      OpenSSL::Digest::SHA256.digest("#{encoded_header}.#{encoded_claims}"),
      raw_signature_to_der(Base64.urlsafe_decode64(encoded_signature))
    )
  end

  def test_fetch_reviews_follows_pagination_without_a_rating_filter
    calls = []
    pages = [
      {
        "data" => [review("first")],
        "included" => [response("response-first")],
        "links" => { "next" => "https://example.test/next" }
      },
      { "data" => [review("second", response_id: nil)], "links" => {} }
    ]
    get = lambda do |url, token|
      calls << [url, token]
      pages.shift
    end

    reviews = AppStoreReviewSync.fetch_reviews(app_id: "6800438206", token: "token", get: get)

    assert_equal %w[first second], reviews.map { |item| item.first["id"] }
    assert_equal "response-first", reviews.first.last["id"]
    assert_nil reviews.last.last
    assert_includes calls.first.first, "/v1/apps/6800438206/customerReviews?"
    refute_includes calls.first.first, "filter%5Brating%5D"
    assert_equal "https://example.test/next", calls.last.first
  end

  def test_issue_contains_all_review_and_response_fields
    body = AppStoreReviewSync.issue_body(review("review-1"), response("response-review-1"))

    assert_includes body, "<!-- app-store-review-id:review-1 -->"
    assert_includes body, "Excellent"
    assert_includes body, "Every expected detail is present."
    assert_includes body, "Reviewer"
    assert_includes body, "USA"
    assert_includes body, "Thanks for the review!"
    assert_includes body, "PUBLISHED"
    assert_includes body, "Raw App Store Connect data"
  end

  private

  def review(id, response_id: "response-#{id}")
    relationships = response_id ? { "response" => { "data" => { "id" => response_id } } } : {}
    {
      "type" => "customerReviews",
      "id" => id,
      "attributes" => {
        "rating" => 5,
        "title" => "Excellent",
        "body" => "Every expected detail is present.",
        "reviewerNickname" => "Reviewer",
        "createdDate" => "2026-08-13T12:00:00Z",
        "territory" => "USA"
      },
      "relationships" => relationships,
      "links" => { "self" => "https://example.test/reviews/#{id}" }
    }
  end

  def response(id)
    {
      "type" => "customerReviewResponses",
      "id" => id,
      "attributes" => {
        "responseBody" => "Thanks for the review!",
        "lastModifiedDate" => "2026-08-13T13:00:00Z",
        "state" => "PUBLISHED"
      }
    }
  end

  def decode_json(value)
    JSON.parse(Base64.urlsafe_decode64(value))
  end

  def raw_signature_to_der(signature)
    half = signature.bytesize / 2
    OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(OpenSSL::BN.new(signature.byteslice(0, half), 2)),
      OpenSSL::ASN1::Integer(OpenSSL::BN.new(signature.byteslice(half, half), 2))
    ]).to_der
  end
end
