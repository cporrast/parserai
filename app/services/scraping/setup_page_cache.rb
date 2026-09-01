require "digest"

module Scraping
  class SetupPageCache
    def initialize(fetcher: PageFetcher.new, content_extractor: ContentExtractor.new)
      @fetcher = fetcher
      @content_extractor = content_extractor
    end

    def fetch(url, refresh: false)
      normalized_url = url.to_s.strip
      snapshot = SetupPageSnapshot.find_or_create_by!(url_digest: Digest::SHA256.hexdigest(normalized_url)) do |record|
        record.url = normalized_url
      end
      return snapshot if snapshot.fresh? && !refresh

      snapshot.with_lock do
        return snapshot if snapshot.fresh? && !refresh

        request_url = snapshot.final_url.presence || normalized_url
        page = @fetcher.fetch(
          request_url,
          etag: snapshot.etag,
          last_modified: snapshot.last_modified
        )
        if page.not_modified?
          snapshot.update!(
            http_status: page.status,
            etag: page.etag,
            last_modified: page.last_modified,
            fetched_at: Time.current
          )
          return snapshot
        end

        content_digest = Digest::SHA256.hexdigest(page.body)
        if snapshot.content_digest == content_digest && snapshot.raw_html.present?
          snapshot.update!(
            final_url: page.url,
            http_status: page.status,
            content_type: page.content_type,
            etag: page.etag,
            last_modified: page.last_modified,
            fetched_at: Time.current
          )
          return snapshot
        end

        content = @content_extractor.extract(page.body, base_url: page.url)
        snapshot.update!(
          url: normalized_url, final_url: page.url, http_status: page.status, content_type: page.content_type,
          title: content.title, raw_html: page.body, extracted_text: content.text,
          structured_data: content.structured_data, fetched_at: Time.current,
          etag: page.etag, last_modified: page.last_modified, content_digest:,
          schema_cache_key: nil, selector_rules_cache_key: nil,
          suggested_schema: nil, suggested_rules: nil,
          schema_generated_at: nil, selector_rules_generated_at: nil
        )
      end
      snapshot
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end
end
