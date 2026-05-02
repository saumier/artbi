class VenuesController < ApplicationController
  def index
    @search_query = params[:q]
    @page         = [ params[:page].to_i, 1 ].max
    @entities     = ArtsDataService.new.fetch_venues(q: @search_query, page: @page)

    if params[:infinite].present?
      return head(:no_content) if @entities.empty?
      render partial: "card", collection: @entities, as: :entity, layout: false
    end
  end

  def show
    @uri = params[:uri].to_s.strip
    return redirect_to venues_path if @uri.blank?

    service  = ArtsDataService.new
    @entity  = service.fetch_entity_details(uri: @uri)
    return redirect_to venues_path unless @entity

    @page   = [ params[:page].to_i, 1 ].max
    @events = service.fetch_entity_events(
      uri:          @uri,
      predicates:   %w[schema:location],
      image_filter: :with,
      page:         @page,
      limit:        6
    )

    if params[:infinite].present?
      return head(:no_content) if @events.empty?
      render partial: "events/card", collection: @events, as: :event, layout: false
    end

    @events_table = service.fetch_entity_events(
      uri:          @uri,
      predicates:   %w[schema:location],
      image_filter: :without,
      limit:        200
    )
  end
end
