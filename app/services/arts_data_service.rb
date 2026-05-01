require "net/http"
require "json"
require "uri"

class ArtsDataService
  ENDPOINT = "https://query.artsdata.ca/query"
  PER_PAGE  = 12

  PROVINCE_TIMEZONES = {
    "AB" => "Mountain Time (US & Canada)",
    "BC" => "Pacific Time (US & Canada)",
    "MB" => "Central Time (US & Canada)",
    "NB" => "Atlantic Time (Canada)",
    "NL" => "Newfoundland",
    "NS" => "Atlantic Time (Canada)",
    "NT" => "Mountain Time (US & Canada)",
    "NU" => "Eastern Time (US & Canada)",
    "ON" => "Eastern Time (US & Canada)",
    "PE" => "Atlantic Time (Canada)",
    "QC" => "Eastern Time (US & Canada)",
    "SK" => "Saskatchewan",
    "YT" => "Pacific Time (US & Canada)"
  }.freeze

  PROVINCE_NAMES = {
    "AB" => "Alberta",
    "BC" => "Colombie-Britannique",
    "MB" => "Manitoba",
    "NB" => "Nouveau-Brunswick",
    "NL" => "Terre-Neuve-et-Labrador",
    "NS" => "Nouvelle-Écosse",
    "NT" => "Territoires du Nord-Ouest",
    "NU" => "Nunavut",
    "ON" => "Ontario",
    "PE" => "Île-du-Prince-Édouard",
    "QC" => "Québec",
    "SK" => "Saskatchewan",
    "YT" => "Yukon"
  }.freeze

  # Maps every known full-name variant (EN/FR) → 2-letter code for normalisation.
  PROVINCE_CODES = PROVINCE_NAMES.invert.merge(
    "Alberta"                      => "AB",
    "British Columbia"             => "BC",
    "Colombie-Britannique"         => "BC",
    "Manitoba"                     => "MB",
    "New Brunswick"                => "NB",
    "Nouveau-Brunswick"            => "NB",
    "Newfoundland"                 => "NL",
    "Newfoundland and Labrador"    => "NL",
    "Terre-Neuve-et-Labrador"      => "NL",
    "Nova Scotia"                  => "NS",
    "Nouvelle-Écosse"              => "NS",
    "Northwest Territories"        => "NT",
    "Territoires du Nord-Ouest"    => "NT",
    "Nunavut"                      => "NU",
    "Ontario"                      => "ON",
    "Prince Edward Island"         => "PE",
    "Île-du-Prince-Édouard"        => "PE",
    "Quebec"                       => "QC",
    "Québec"                       => "QC",
    "Saskatchewan"                 => "SK",
    "Yukon"                        => "YT"
  ).freeze

  def fetch_events(q: nil, date_from: nil, date_to: nil, location: nil, location_type: nil, page: 1)
    from_date = date_from.present? ? "#{date_from}T00:00:00" : "#{Date.today}T00:00:00"
    offset    = (page.to_i - 1) * PER_PAGE

    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      PREFIX xsd:    <http://www.w3.org/2001/XMLSchema#>
      SELECT ?event
             (SAMPLE(?rawName)         AS ?name)
             ?startDate
             ?endDate
             (SAMPLE(?rawImage)        AS ?image)
             (SAMPLE(?rawUrl)          AS ?url)
             (SAMPLE(?rawLocName)      AS ?locationName)
             (SAMPLE(?rawCity)         AS ?city)
             (SAMPLE(?rawProvince)     AS ?province)
             (SAMPLE(?rawStatus)       AS ?status)
             (SAMPLE(?rawType)         AS ?type)
      FROM <http://kg.artsdata.ca/core>
      WHERE {
        ?event a schema:Event .
        ?event schema:name ?rawName .
        ?event schema:startDate ?startDate .
        FILTER(datatype(?startDate) = xsd:dateTime)
        FILTER(?startDate >= "#{from_date}"^^xsd:dateTime)
        #{keyword_clause(q)}
        #{date_to_clause(date_to)}
        OPTIONAL { ?event schema:endDate ?endDate }
        OPTIONAL { ?event schema:image ?imgNode . ?imgNode schema:url ?rawImage }
        OPTIONAL { ?event schema:url ?rawUrl }
        OPTIONAL { ?event schema:eventStatus ?rawStatus }
        OPTIONAL { ?event schema:additionalType ?rawType }
        OPTIONAL {
          ?event schema:location ?loc .
          OPTIONAL { ?loc schema:name ?rawLocName }
          OPTIONAL {
            ?loc schema:address ?addr .
            OPTIONAL { ?addr schema:addressLocality ?rawCity }
            OPTIONAL { ?addr schema:addressRegion    ?rawProvince }
          }
        }
        #{location_clause(location, location_type)}
      }
      GROUP BY ?event ?startDate ?endDate
      ORDER BY ?startDate
      LIMIT #{PER_PAGE}
      OFFSET #{offset}
    SPARQL

    execute_events(sparql)
  end

  def fetch_event_details(uri:)
    return nil if uri.blank?

    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      SELECT ?description ?image ?sameAs
             ?performer ?performerName ?org ?organizerName ?keyword ?type ?status
      FROM <http://kg.artsdata.ca/core>
      WHERE {
       values ?event { <#{uri}> }
        OPTIONAL { ?event schema:description ?description }
        OPTIONAL { ?event schema:image ?imgNode . ?imgNode schema:url ?image }
        OPTIONAL { ?event schema:sameAs ?sameAs }
        OPTIONAL { ?event schema:performer ?performer . ?performer schema:name ?performerName }
        OPTIONAL { ?event schema:organizer ?org . ?org schema:name ?organizerName }
        OPTIONAL { ?event schema:keywords ?keyword }
        OPTIONAL { ?event schema:additionalType ?type }
        OPTIONAL { ?event schema:eventStatus ?status }
      }
      LIMIT 50
    SPARQL

    data = sparql_request(sparql)
    return nil unless data
    parse_event_details(data)
  rescue => e
    Rails.logger.error("ArtsDataService#fetch_event_details error: #{e.message}")
    nil
  end

  # Returns filtered autocomplete suggestions as an array of hashes:
  #   { label:, type: "city"|"province", value:, province_code: }
  def fetch_locations(q: nil)
    all = cached_locations
    return all.first(12) if q.blank?

    q_down = q.downcase.strip
    matches = all.select { |l| l[:label].downcase.include?(q_down) }
    matches.sort_by { |l|
      idx = l[:label].downcase.index(q_down) || 999
      [ idx, l[:label] ]
    }.first(12)
  end

  private

  # ── Query builders ──────────────────────────────────────────────

  def keyword_clause(q)
    return "" unless q.present?
    safe = sanitize_sparql(q)
    return "" if safe.blank?
    "FILTER(CONTAINS(LCASE(STR(?rawName)), LCASE(\"#{safe}\")))"
  end

  def date_to_clause(date_to)
    return "" unless date_to.present?
    "FILTER(?startDate <= \"#{date_to}T23:59:59\"^^xsd:dateTime)"
  end

  def location_clause(location, location_type)
    return "" unless location.present?
    safe = sanitize_sparql(location)
    return "" if safe.blank?

    if location_type == "province"
      # Match the 2-letter code plus every full-name variant stored in the graph
      variants = province_variants(safe).map { |v| "\"#{sanitize_sparql(v)}\"" }.join(", ")
      "FILTER(BOUND(?rawProvince) && STR(?rawProvince) IN (#{variants}))"
    else
      "FILTER(BOUND(?rawCity) && LCASE(STR(?rawCity)) = LCASE(\"#{safe}\"))"
    end
  end

  def sanitize_sparql(str)
    str.gsub(/["'\\<>{}|^`]/, "").strip
  end

  # Returns all raw strings the graph might use for a given province code.
  def province_variants(code)
    variants = [ code ]
    variants << PROVINCE_NAMES[code] if PROVINCE_NAMES[code]
    PROVINCE_CODES.each { |full, c| variants << full if c == code }
    variants.uniq
  end

  # ── HTTP / parsing ───────────────────────────────────────────────

  def execute_events(sparql)
    data = sparql_request(sparql)
    return [] unless data
    parse_events(data)
  rescue => e
    Rails.logger.error("ArtsDataService#fetch_events error: #{e.message}")
    []
  end

  def sparql_request(sparql)
    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form(query: sparql, format: "json")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request["Accept"] = "application/sparql-results+json"

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("ArtsData HTTP #{response.code}: #{response.body.truncate(200)}")
      return nil
    end
    JSON.parse(response.body)
  end

  def parse_events(data)
    labels = cached_type_labels
    (data.dig("results", "bindings") || []).map do |b|
      type_uri     = b.dig("type", "value")
      province_raw = b.dig("province", "value")
      province     = PROVINCE_CODES[province_raw] || province_raw
      start_raw    = b.dig("startDate", "value")
      {
        uri:           b.dig("event",        "value"),
        name:          b.dig("name",         "value"),
        start_date:    parse_date(start_raw),
        start_time:    parse_local_time(start_raw, province),
        end_date:      parse_date(b.dig("endDate", "value")),
        image:         b.dig("image",        "value"),
        url:           b.dig("url",          "value"),
        location_name: b.dig("locationName", "value"),
        city:          b.dig("city",         "value"),
        province:      province,
        status:        uri_local(b.dig("status", "value")),
        type:          labels[type_uri]
      }
    end
  end

  def parse_date(str)
    return nil unless str.present?
    DateTime.parse(str)
  rescue ArgumentError
    nil
  end

  def parse_local_time(raw_str, province_code)
    return nil unless raw_str.present?
    tz_name = PROVINCE_TIMEZONES[province_code]
    return nil unless tz_name
    tz = ActiveSupport::TimeZone[tz_name]
    has_offset = raw_str.end_with?("Z") || raw_str.match?(/[+-]\d{2}:?\d{2}$/)
    has_offset ? DateTime.parse(raw_str).in_time_zone(tz) : tz.parse(raw_str)
  rescue ArgumentError
    nil
  end

  def uri_local(uri)
    uri&.split("/")&.last
  end

  def humanize_type(uri)
    return nil unless uri.present?
    uri_local(uri)
      .gsub(/([A-Z])/, ' \1')
      .strip
      .gsub(" Event", "")
      .presence
  end

  def parse_event_details(data)
    labels         = cached_type_labels
    bindings       = data.dig("results", "bindings") || []
    return nil if bindings.empty?

    result = {
      description: nil,
      image:       nil,
      url:         nil,
      same_as:     [],
      performers:  [],
      organizers:  [],
      keywords:    [],
      types:       [],
      status:      nil
    }

    performers_by_entity = {}
    organizers_by_entity = {}

    bindings.each do |b|
      result[:description] ||= b.dig("description", "value")
      result[:image]       ||= b.dig("image",       "value")
      result[:url]         ||= b.dig("url",         "value")
      result[:status]      ||= uri_local(b.dig("status", "value"))

      add_unique(result[:same_as],  b.dig("sameAs",   "value"))
      add_unique(result[:keywords], b.dig("keyword",  "value"))

      collect_lang_name(performers_by_entity,
                        b.dig("performer",     "value"),
                        b.dig("performerName", "value"),
                        b.dig("performerName", "xml:lang").to_s)

      collect_lang_name(organizers_by_entity,
                        b.dig("org",           "value"),
                        b.dig("organizerName", "value"),
                        b.dig("organizerName", "xml:lang").to_s)

      type_uri = b.dig("type", "value")
      if type_uri.present?
        label = labels[type_uri] || humanize_type(type_uri)
        add_unique(result[:types], label)
      end
    end

    result[:performers] = preferred_lang_names(performers_by_entity)
    result[:organizers] = preferred_lang_names(organizers_by_entity)
    result
  end

  def collect_lang_name(hash, entity_key, name, lang)
    return unless (entity_key || name).present? && name.present?
    key = entity_key.presence || name
    hash[key] ||= {}
    if lang.start_with?("fr")
      hash[key][:fr] = name
    elsif lang.start_with?("en")
      hash[key][:en] ||= name
    else
      hash[key][:other] ||= name
    end
  end

  def preferred_lang_names(hash)
    hash.values.filter_map { |names| names[:fr] || names[:en] || names[:other] }.uniq
  end

  def add_unique(arr, value)
    arr << value if value.present? && !arr.include?(value)
  end

  # ── Type-label cache ─────────────────────────────────────────────

  def cached_type_labels
    Rails.cache.fetch("artsdata_type_labels_v3", expires_in: 12.hours) do
      fetch_all_type_labels
    end
  end

  def fetch_all_type_labels
    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      PREFIX skos:   <http://www.w3.org/2004/02/skos/core#>
      SELECT DISTINCT ?type ?label
      WHERE {
        ?event a schema:Event .
        ?event schema:additionalType ?type .
        { ?type schema:name ?label }
        UNION
        { ?type skos:prefLabel ?label }
      }
    SPARQL

    data = sparql_request(sparql)
    return {} unless data

    # Build map: type_uri => { label:, lang: }, preferring fr > en > any other
    best = {}
    (data.dig("results", "bindings") || []).each do |b|
      uri   = b.dig("type",  "value")
      label = b.dig("label", "value")
      lang  = b.dig("label", "xml:lang").to_s
      next unless uri.present? && label.present?

      current = best[uri]
      if current.nil? ||
         (lang.start_with?("fr")) ||
         (lang.start_with?("en") && !current[:lang].start_with?("fr"))
        best[uri] = { label: label, lang: lang }
      end
    end

    best.transform_values { |v| v[:label] }
  end

  # ── Locations cache ──────────────────────────────────────────────

  def cached_locations
    Rails.cache.fetch("artsdata_locations_v1", expires_in: 6.hours) do
      fetch_all_locations
    end
  end

  def fetch_all_locations
    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      SELECT DISTINCT ?city ?province
      FROM <http://kg.artsdata.ca/core>
      WHERE {
        ?event a schema:Event .
        ?event schema:location ?loc .
        ?loc schema:address ?addr .
        OPTIONAL { ?addr schema:addressLocality ?city }
        OPTIONAL { ?addr schema:addressRegion    ?province }
        FILTER(BOUND(?city) || BOUND(?province))
      }
      LIMIT 2000
    SPARQL

    data = sparql_request(sparql)
    return [] unless data

    city_province = {}   # city => province_code (normalised)
    provinces     = {}   # normalised code => true

    (data.dig("results", "bindings") || []).each do |b|
      city = b.dig("city",     "value")&.strip.presence
      prov = b.dig("province", "value")&.strip.presence

      if prov
        prov = PROVINCE_CODES[prov] || prov   # normalise to 2-letter code
        provinces[prov] = true
      end

      city_province[city] ||= prov if city
    end

    result = []

    # Provinces first (mapped to full names where possible)
    provinces.keys.sort_by { |c| PROVINCE_NAMES[c] || c }.each do |code|
      label = PROVINCE_NAMES[code] || code
      result << { label: label, type: "province", value: code }
    end

    # Cities sorted alphabetically
    city_province.keys.sort.each do |city|
      prov_code  = city_province[city]
      prov_label = PROVINCE_NAMES[prov_code] || prov_code
      result << { label: city, type: "city", value: city, province: prov_label }
    end

    result
  end
end
