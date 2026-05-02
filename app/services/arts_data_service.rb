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

  def fetch_events(q: nil, date_from: nil, date_to: nil, location: nil, location_type: nil, concept_uri: nil, page: 1)
    from_date    = date_from.present? ? "#{date_from}T00:00:00" : "#{Date.today}T00:00:00"
    offset       = (page.to_i - 1) * PER_PAGE
    concept_uris = concept_uri.present? ? expand_concept(concept_uri, cached_type_taxonomy) : []

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
             (GROUP_CONCAT(DISTINCT STR(?anyType); SEPARATOR="|") AS ?types)
             (SAMPLE(?loc)             AS ?locationUri)
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
        OPTIONAL { ?event schema:additionalType ?anyType }
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
        #{concept_clause(concept_uris)}
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

  PER_PAGE_ENTITIES = 24

  # ── Entity listings ──────────────────────────────────────────────

  def fetch_performers(q: nil, page: 1)
    fetch_entity_listing(q: q, page: page,
                         predicates: %w[schema:performer schema:contributor])
  end

  def fetch_presenters(q: nil, page: 1)
    fetch_entity_listing(q: q, page: page,
                         predicates: %w[schema:organizer])
  end

  def fetch_venues(q: nil, page: 1)
    fetch_entity_listing(q: q, page: page,
                         predicates: %w[schema:location], is_venue: true)
  end

  # ── Entity detail ────────────────────────────────────────────────

  def fetch_entity_details(uri:)
    return nil if uri.blank?
    safe = sanitize_sparql(uri)

    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      SELECT ?name ?imgObj ?imgLit ?description ?url ?sameAs ?street ?city ?province ?postalCode
      FROM <http://kg.artsdata.ca/core>
      WHERE {
        VALUES ?entity { <#{safe}> }
        OPTIONAL { ?entity schema:name        ?name        }
        OPTIONAL { ?entity schema:image ?imgNode . ?imgNode schema:url ?imgObj }
        OPTIONAL { ?entity schema:image ?imgLit . FILTER(isLiteral(?imgLit)) }
        OPTIONAL { ?entity schema:description ?description }
        OPTIONAL { ?entity schema:url         ?url         }
        OPTIONAL { ?entity schema:sameAs      ?sameAs      }
        OPTIONAL {
          ?entity schema:address ?addr .
          OPTIONAL { ?addr schema:streetAddress   ?street     }
          OPTIONAL { ?addr schema:addressLocality ?city       }
          OPTIONAL { ?addr schema:addressRegion   ?province   }
          OPTIONAL { ?addr schema:postalCode      ?postalCode }
        }
      }
      LIMIT 30
    SPARQL

    data = sparql_request(sparql)
    return nil unless data
    parse_entity_details(data, uri)
  rescue => e
    Rails.logger.error("ArtsDataService#fetch_entity_details error: #{e.message}")
    nil
  end

  # ── Events for an entity ─────────────────────────────────────────

  def fetch_entity_events(uri:, predicates:, page: 1, image_filter: :any, limit: nil)
    return [] if uri.blank? || predicates.blank?
    actual_limit = limit || PER_PAGE
    safe   = sanitize_sparql(uri)
    offset = (page.to_i - 1) * actual_limit
    union  = predicates.map { |p| "{ ?event #{p} <#{safe}> }" }.join("\n    UNION\n    ")
    img_clause = case image_filter
    when :with    then "FILTER EXISTS     { ?event schema:image ?_ic . ?_ic schema:url ?_iu }"
    when :without then "FILTER NOT EXISTS { ?event schema:image ?_ic . ?_ic schema:url ?_iu }"
    else               ""
    end

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
             (GROUP_CONCAT(DISTINCT STR(?anyType); SEPARATOR="|") AS ?types)
             (SAMPLE(?loc)             AS ?locationUri)
      FROM <http://kg.artsdata.ca/core>
      WHERE {
        ?event a schema:Event .
        #{union}
        ?event schema:name      ?rawName .
        ?event schema:startDate ?startDate .
        FILTER(datatype(?startDate) = xsd:dateTime)
        #{img_clause}
        OPTIONAL { ?event schema:endDate ?endDate }
        OPTIONAL { ?event schema:image ?imgNode . ?imgNode schema:url ?rawImage }
        OPTIONAL { ?event schema:url ?rawUrl }
        OPTIONAL { ?event schema:eventStatus ?rawStatus }
        OPTIONAL { ?event schema:additionalType ?anyType }
        OPTIONAL {
          ?event schema:location ?loc .
          OPTIONAL { ?loc schema:name ?rawLocName }
          OPTIONAL {
            ?loc schema:address ?addr .
            OPTIONAL { ?addr schema:addressLocality ?rawCity }
            OPTIONAL { ?addr schema:addressRegion    ?rawProvince }
          }
        }
      }
      GROUP BY ?event ?startDate ?endDate
      ORDER BY ?startDate
      LIMIT #{actual_limit}
      OFFSET #{offset}
    SPARQL

    data = sparql_request(sparql)
    return [] unless data
    parse_events(data)
  rescue => e
    Rails.logger.error("ArtsDataService#fetch_entity_events error: #{e.message}")
    []
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
    labels   = cached_type_labels
    taxonomy = cached_type_taxonomy
    (data.dig("results", "bindings") || []).map do |b|
      type_uris    = b.dig("types", "value").to_s.split("|").select(&:present?)
      best_uri     = most_specific_type(type_uris, taxonomy)
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
        type:          labels[best_uri],
        type_uri:      best_uri,
        location_uri:  b.dig("locationUri", "value")
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
        result[:types] << { uri: type_uri, label: label } unless result[:types].any? { |t| t[:uri] == type_uri }
      end
    end

    result[:performers] = preferred_lang_entities(performers_by_entity)
    result[:organizers] = preferred_lang_entities(organizers_by_entity)
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

  def preferred_lang_entities(hash)
    hash.filter_map do |key, names|
      name = names[:fr] || names[:en] || names[:other]
      next unless name.present?
      uri = (key.is_a?(String) && key.start_with?("http")) ? key : nil
      { uri: uri, name: name }
    end.uniq { |e| e[:name] }
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

  # ── Type taxonomy cache ──────────────────────────────────────────

  def cached_type_taxonomy
    Rails.cache.fetch("artsdata_type_taxonomy_v2", expires_in: 12.hours) do
      fetch_type_taxonomy
    end
  end

  def fetch_type_taxonomy
    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      PREFIX skos:   <http://www.w3.org/2004/02/skos/core#>
      SELECT DISTINCT ?type ?broader ?narrower ?closeMatch ?exactMatch
      WHERE {
        ?event a schema:Event .
        ?event schema:additionalType ?type .
        OPTIONAL { ?type skos:broader    ?broader    }
        OPTIONAL { ?type skos:narrower   ?narrower   }
        OPTIONAL { ?type skos:closeMatch ?closeMatch }
        OPTIONAL { ?type skos:exactMatch ?exactMatch }
      }
    SPARQL

    data = sparql_request(sparql)
    return {} unless data

    map = {}
    (data.dig("results", "bindings") || []).each do |b|
      type = b.dig("type", "value")
      next unless type.present?
      entry = map[type] ||= { broader: [], narrower: [], close_match: [], exact_match: [] }
      add_unique(entry[:broader],     b.dig("broader",     "value"))
      add_unique(entry[:narrower],    b.dig("narrower",    "value"))
      add_unique(entry[:close_match], b.dig("closeMatch",  "value"))
      add_unique(entry[:exact_match], b.dig("exactMatch",  "value"))
    end
    map
  end

  # Returns the most specific URI from a list using skos:broader ancestry.
  # A type is dropped if it is an ancestor of any other type in the set.
  # Among equally specific candidates, artsdata.ca URIs are preferred.
  def most_specific_type(type_uris, taxonomy)
    return type_uris.first if type_uris.size <= 1

    ancestors_of = type_uris.index_with { |t| type_ancestors(t, taxonomy) }

    candidates = type_uris.reject do |t|
      type_uris.any? { |other| other != t && ancestors_of[other].include?(t) }
    end
    candidates = type_uris if candidates.empty?

    candidates.find { |t| t.include?("artsdata.ca") } || candidates.first
  end

  def type_ancestors(type_uri, taxonomy, visited = Set.new)
    (taxonomy.dig(type_uri, :broader) || []).each do |parent|
      next if visited.include?(parent)
      visited.add(parent)
      type_ancestors(parent, taxonomy, visited)
    end
    visited
  end

  # Expands a concept URI to itself + all narrower (recursive) + closeMatch + exactMatch.
  def expand_concept(uri, taxonomy)
    result = Set.new([ uri ])
    collect_narrower(uri, taxonomy, result)
    (taxonomy.dig(uri, :close_match) || []).each { |m| result.add(m) }
    (taxonomy.dig(uri, :exact_match) || []).each { |m| result.add(m) }
    result.to_a
  end

  def collect_narrower(uri, taxonomy, visited)
    (taxonomy.dig(uri, :narrower) || []).each do |child|
      next if visited.include?(child)
      visited.add(child)
      collect_narrower(child, taxonomy, visited)
    end
  end

  def concept_clause(concept_uris)
    return "" unless concept_uris.present?
    safe = concept_uris
      .select { |u| u.match?(/\Ahttps?:\/\/[^\s"'<>\\]+\z/) }
      .map    { |u| "<#{u}>" }
      .join(", ")
    return "" if safe.blank?
    "FILTER EXISTS { ?event schema:additionalType ?conceptType . FILTER(?conceptType IN (#{safe})) }"
  end

  # ── Entity listing / detail helpers ─────────────────────────────

  def fetch_entity_listing(q:, page:, predicates:, is_venue: false)
    offset       = (page.to_i - 1) * PER_PAGE_ENTITIES
    safe_q       = q.present? ? sanitize_sparql(q) : nil
    union        = predicates.map { |p| "{ ?event #{p} ?entity }" }.join("\n    UNION\n    ")
    kw_filter    = safe_q.present? ? "FILTER(CONTAINS(LCASE(STR(?rawName)), LCASE(\"#{safe_q}\")))" : ""
    venue_select = is_venue ? "(SAMPLE(?rawCity) AS ?city) (SAMPLE(?rawProvince) AS ?province)" : ""
    venue_opt    = is_venue ? "OPTIONAL { ?entity schema:address ?addr . OPTIONAL { ?addr schema:addressLocality ?rawCity } OPTIONAL { ?addr schema:addressRegion ?rawProvince } }" : ""

    sparql = <<~SPARQL
      PREFIX schema: <http://schema.org/>
      SELECT ?entity
             (SAMPLE(?rawName) AS ?name)
             (COALESCE(SAMPLE(?rawImgObj), SAMPLE(?rawImgLit)) AS ?image)
             #{venue_select}
             (COUNT(DISTINCT ?event) AS ?eventCount)
      FROM <http://kg.artsdata.ca/core>
      WHERE {
        ?event a schema:Event .
        #{union}
        ?entity schema:name ?rawName .
        #{kw_filter}
        OPTIONAL { ?entity schema:image ?imgNode . ?imgNode schema:url ?rawImgObj }
        OPTIONAL { ?entity schema:image ?rawImgLit . FILTER(isLiteral(?rawImgLit)) }
        #{venue_opt}
      }
      GROUP BY ?entity
      ORDER BY ?name
      LIMIT #{PER_PAGE_ENTITIES}
      OFFSET #{offset}
    SPARQL

    data = sparql_request(sparql)
    return [] unless data
    parse_entity_listing(data, is_venue: is_venue)
  rescue => e
    Rails.logger.error("ArtsDataService#fetch_entity_listing error: #{e.message}")
    []
  end

  def parse_entity_listing(data, is_venue: false)
    (data.dig("results", "bindings") || []).filter_map do |b|
      name = b.dig("name", "value")
      next unless name.present?
      h = {
        uri:         b.dig("entity",     "value"),
        name:        name,
        image:       b.dig("image",      "value"),
        event_count: b.dig("eventCount", "value").to_i
      }
      if is_venue
        prov_raw    = b.dig("province", "value")
        h[:city]     = b.dig("city", "value")
        h[:province] = PROVINCE_CODES[prov_raw] || prov_raw
      end
      h
    end
  end

  def parse_entity_details(data, uri)
    bindings = data.dig("results", "bindings") || []
    return nil if bindings.empty?

    result = { uri: uri, name: nil, image: nil, description: nil,
               url: nil, same_as: [], street: nil, city: nil,
               province: nil, postal_code: nil }

    names_by_lang = {}
    descs_by_lang = {}

    bindings.each do |b|
      collect_lang_name(names_by_lang, uri,
                        b.dig("name", "value"),
                        b.dig("name", "xml:lang").to_s)
      collect_lang_name(descs_by_lang, uri,
                        b.dig("description", "value"),
                        b.dig("description", "xml:lang").to_s)

      result[:image]       ||= b.dig("imgObj", "value").presence || b.dig("imgLit", "value")
      result[:url]         ||= b.dig("url",     "value")
      result[:street]      ||= b.dig("street",  "value")
      result[:postal_code] ||= b.dig("postalCode", "value")
      add_unique(result[:same_as], b.dig("sameAs", "value"))

      prov_raw = b.dig("province", "value")
      result[:city]     ||= b.dig("city", "value")
      result[:province] ||= PROVINCE_CODES[prov_raw] || prov_raw if prov_raw.present?
    end

    result[:name]        = preferred_lang_names(names_by_lang).first
    result[:description] = preferred_lang_names(descs_by_lang).first
    result[:name].present? ? result : nil
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
