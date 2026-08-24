module ApplicationHelper
  def safe_image_url(url)
    return nil if url.blank? || url == "N/A"
    uri = URI.parse(url.to_s)
    uri.scheme&.match?(/\Ahttps?\z/) ? url : nil
  rescue URI::InvalidURIError
    nil
  end

  def safe_external_url(url)
    return "#" if url.blank? || url == "N/A"
    uri = URI.parse(url.to_s)
    uri.scheme&.match?(/\Ahttps?\z/) ? url : "#"
  rescue URI::InvalidURIError
    "#"
  end
end
