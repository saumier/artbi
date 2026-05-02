class EventsController < ApplicationController
  DATE_RANGE_LABELS = {
    "today" => "Aujourd'hui",
    "week"  => "Cette semaine"
  }.freeze

  def index
    @search_query   = params[:q]
    @date_range     = params[:date_range].presence || "all"
    @date_from      = params[:date_from]
    @date_to        = params[:date_to]
    @location       = params[:location]
    @location_type  = params[:location_type]
    @location_label = params[:location_label]
    @concept_uri    = params[:concept_uri]
    @concept_label  = params[:concept_label]
    @page           = [ params[:page].to_i, 1 ].max

    effective_from, effective_to = resolve_date_range

    @events = ArtsDataService.new.fetch_events(
      q:             @search_query,
      date_from:     effective_from,
      date_to:       effective_to,
      location:      @location,
      location_type: @location_type,
      concept_uri:   @concept_uri,
      page:          @page
    )

    if params[:infinite].present?
      return head(:no_content) if @events.empty?
      render partial: "card", collection: @events, as: :event, layout: false
    end
  end

  def details
    url   = params[:url].to_s.strip
    uri  = params[:uri].to_s.strip
    image = params[:image].to_s.strip

    details = uri.present? ? ArtsDataService.new.fetch_event_details(uri: uri) : nil
    details ||= {}

    details[:url]           = url.presence   if details[:url].blank?
    details[:image]         = image.presence if details[:image].blank?
    details[:same_as]       ||= []
    details[:performers]    ||= []
    details[:organizers]    ||= []
    details[:keywords]      ||= []
    details[:types]         ||= []

    details[:uri]           = uri.presence  if details[:uri].blank?
    details[:start_date]    = params[:start_date].to_s.presence
    details[:start_time]    = params[:start_time].to_s.presence
    details[:end_date]      = params[:end_date].to_s.presence
    details[:location_name] = params[:location_name].to_s.presence
    details[:city]          = params[:city].to_s.presence
    details[:province]      = params[:province].to_s.presence

    render partial: "event_details", locals: { details: details }
  end

  def locations
    q = params[:q].to_s.strip
    results = ArtsDataService.new.fetch_locations(q: q)
    render json: results
  end

  private

  def resolve_date_range
    today = Date.today
    case @date_range
    when "today"  then [ today.to_s,              today.to_s ]
    when "week"   then [ today.to_s,              today.end_of_week.to_s ]
    when "custom" then [ @date_from,              @date_to ]
    else               [ nil,                     nil ]   # all upcoming
    end
  end
end
