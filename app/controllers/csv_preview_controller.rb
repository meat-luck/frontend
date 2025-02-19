require "csv"

class CsvPreviewController < ApplicationController
  MAXIMUM_COLUMNS = 50
  MAXIMUM_ROWS = 1000

  rescue_from GdsApi::HTTPForbidden, with: :access_limited

  def show
    @asset = GdsApi.asset_manager.whitehall_asset(legacy_url_path).to_hash

    if draft_asset? && !served_from_draft_host?
      redirect_to(Plek.find("draft-assets") + request.path, allow_other_host: true) and return
    end

    original_error = nil
    row_sep = :auto
    begin
      csv_preview = CSV.parse(media, encoding:, headers: true, row_sep:)
    rescue CSV::MalformedCSVError => e
      if original_error.nil?
        original_error = e
        row_sep = "\r\n"
        retry
      else
        raise original_error
      end
    end

    @csv_rows = csv_preview.to_a.map { |row|
      row.map { |column|
        {
          text: column&.encode("UTF-8"),
        }
      }.take(MAXIMUM_COLUMNS)
    }.take(MAXIMUM_ROWS + 1)

    parent_document_path = URI(@asset["parent_document_url"]).request_uri
    @content_item = GdsApi.content_store.content_item(parent_document_path).to_hash

    @attachment_metadata = @content_item.dig("details", "attachments").select do |attachment|
      attachment["url"] =~ /#{Regexp.escape(legacy_url_path)}$/
    end
  end

  def access_limited
    render :access_limited, status: :forbidden and return
  end

private

  def legacy_url_path
    request.path.sub("/preview", "").sub(/^\//, "")
  end

  def media
    GdsApi.asset_manager.whitehall_media(legacy_url_path).body
  end

  def encoding
    @encoding ||= if utf_8_encoding?
                    "UTF-8"
                  elsif windows_1252_encoding?
                    "windows-1252"
                  else
                    raise FileEncodingError, "File encoding not recognised"
                  end
  end

  def utf_8_encoding?
    media.force_encoding("utf-8").valid_encoding?
  end

  def windows_1252_encoding?
    media.force_encoding("windows-1252").valid_encoding?
  end

  def draft_asset?
    @asset["draft"] == true
  end

  def served_from_draft_host?
    request.hostname == URI.parse(Plek.find("draft-assets")).hostname
  end
end
