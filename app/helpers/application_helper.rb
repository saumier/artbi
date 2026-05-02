module ApplicationHelper
  MONTHS_FR = %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre].freeze

  def modal_date_str(date)
    return "" unless date
    "#{date.day} #{MONTHS_FR[date.month - 1]} #{date.year}"
  end

  def modal_time_str(time)
    return "" unless time
    return "" if time.hour == 0 && time.min == 0
    "#{time.strftime('%-H:%M')} #{time.zone}"
  end

  def artsdata_kid(uri)
    last = uri&.split("/")&.last
    last&.start_with?("K") ? last : nil
  end

  SOCIAL_HOSTS = {
    "facebook.com"    => "Facebook",
    "twitter.com"     => "Twitter / X",
    "x.com"           => "Twitter / X",
    "instagram.com"   => "Instagram",
    "youtube.com"     => "YouTube",
    "youtu.be"        => "YouTube",
    "linkedin.com"    => "LinkedIn",
    "tiktok.com"      => "TikTok",
    "eventbrite.ca"   => "Eventbrite",
    "eventbrite.com"  => "Eventbrite",
    "billetterie.ca"  => "Billetterie",
    "admission.com"   => "Admission"
  }.freeze

  def concept_filter_path(concept_uri, concept_label)
    events_path(
      q:              params[:q],
      date_range:     params[:date_range],
      date_from:      params[:date_from],
      date_to:        params[:date_to],
      location:       params[:location],
      location_type:  params[:location_type],
      location_label: params[:location_label],
      concept_uri:    concept_uri,
      concept_label:  concept_label
    )
  end

  def social_label(url)
    host = URI.parse(url).host.to_s.delete_prefix("www.")
    SOCIAL_HOSTS[host] || host.split(".").first.then { |h| h.present? ? h.capitalize : "Lien" }
  rescue URI::InvalidURIError
    "Lien"
  end
end
