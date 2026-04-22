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
    @page           = [ params[:page].to_i, 1 ].max

    effective_from, effective_to = resolve_date_range

    @events = ArtsDataService.new.fetch_events(
      q:             @search_query,
      date_from:     effective_from,
      date_to:       effective_to,
      location:      @location,
      location_type: @location_type,
      page:          @page
    )

    if params[:infinite].present?
      return head(:no_content) if @events.empty?
      render partial: "card", collection: @events, as: :event, layout: false
    end
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
