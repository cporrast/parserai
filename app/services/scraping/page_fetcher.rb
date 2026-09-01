require "ipaddr"
require "net/http"
require "resolv"
require "uri"

module Scraping
  class PageFetcher
    Result = Struct.new(:url, :status, :content_type, :body, :etag, :last_modified, keyword_init: true) do
      def not_modified?
        status == 304
      end
    end

    class FetchError < StandardError; end

    MAX_REDIRECTS = 5
    MAX_BYTES = ENV.fetch("SCRAPER_MAX_RESPONSE_BYTES", 5.megabytes).to_i
    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4
      ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    def initialize(open_timeout: 10, read_timeout: 20)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def fetch(url, redirects: 0, etag: nil, last_modified: nil)
      raise FetchError, "Too many redirects" if redirects > MAX_REDIRECTS

      uri = parse_and_validate(url)
      response = request(uri, etag:, last_modified:)

      case response
      when Net::HTTPNotModified
        Result.new(
          url: uri.to_s,
          status: response.code.to_i,
          content_type: response["content-type"].to_s.split(";").first,
          etag: response["etag"].presence || etag,
          last_modified: response["last-modified"].presence || last_modified
        )
      when Net::HTTPSuccess
        content_type = response["content-type"].to_s.split(";").first
        unless content_type.blank? || content_type.match?(%r{\A(?:text/html|application/xhtml\+xml|text/plain)\z}i)
          raise FetchError, "Unsupported content type: #{content_type}"
        end
        raw_body = response.body.to_s
        raise FetchError, "Response exceeds #{MAX_BYTES} bytes" if raw_body.bytesize > MAX_BYTES

        Result.new(
          url: uri.to_s,
          status: response.code.to_i,
          content_type:,
          body: normalize_body(raw_body, response["content-type"]),
          etag: response["etag"],
          last_modified: response["last-modified"]
        )
      when Net::HTTPRedirection
        location = response["location"]
        raise FetchError, "Redirect did not include a location" if location.blank?

        fetch(URI.join(uri.to_s, location).to_s, redirects: redirects + 1)
      else
        raise FetchError, "Request returned HTTP #{response.code}"
      end
    rescue URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error => e
      raise FetchError, e.message
    end

    private

    def parse_and_validate(url)
      uri = URI.parse(url.to_s.strip)
      raise FetchError, "Only public HTTP and HTTPS URLs are supported" unless %w[http https].include?(uri.scheme)
      raise FetchError, "URL must include a host" if uri.host.blank?
      raise FetchError, "Credentials in URLs are not supported" if uri.userinfo.present?
      raise FetchError, "Local addresses are not allowed" if uri.host.downcase == "localhost" || uri.host.downcase.end_with?(".local")

      addresses = Addrinfo.getaddrinfo(uri.host, uri.port, nil, :STREAM).filter_map(&:ip_address).uniq
      raise FetchError, "Host could not be resolved" if addresses.empty?
      raise FetchError, "Private or reserved network addresses are not allowed" if addresses.any? { |address| blocked_address?(address) }

      uri
    end

    def blocked_address?(address)
      ip = IPAddr.new(address)
      BLOCKED_RANGES.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    def request(uri, etag:, last_modified:)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "ParserAI/0.1 (+personal content processing tool)"
      request["Accept"] = "text/html,application/xhtml+xml,text/plain;q=0.9"
      request["If-None-Match"] = etag if etag.present?
      request["If-Modified-Since"] = last_modified if last_modified.present?

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      ) { |http| http.request(request) }
    end

    def normalize_body(body, content_type)
      source_encoding = detected_encoding(body, content_type)
      body.dup.force_encoding(source_encoding).encode(
        Encoding::UTF_8,
        invalid: :replace,
        undef: :replace,
        replace: "�"
      )
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      body.dup.force_encoding(Encoding::BINARY).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
    end

    def detected_encoding(body, content_type)
      charset = content_type.to_s[/charset\s*=\s*["']?([^;\s"']+)/i, 1]
      charset ||= body.byteslice(0, 4_096).to_s[/<meta[^>]+charset\s*=\s*["']?([^\s"'\/>]+)/i, 1]
      charset ||= body.byteslice(0, 4_096).to_s[/<meta[^>]+content=["'][^"']*charset=([^\s;"']+)/i, 1]
      Encoding.find(charset.presence || "UTF-8")
    rescue ArgumentError
      Encoding::UTF_8
    end
  end
end
