# frozen_string_literal: true

class StatusesSearchService < BaseService
  LOCAL_SEARCH_WINDOW = 50

  def call(query, account = nil, options = {})
    @query   = query&.strip
    @account = account
    @options = options
    @limit   = options[:limit].to_i
    @offset  = options[:offset].to_i

    convert_deprecated_options!
    status_search_results
  end

  private

  def status_search_results
    return local_status_search_results if @options[:local_only]

    request             = parsed_query.request
    results             = request.collapse(field: :id).order(id: { order: :desc }).limit(@limit).offset(@offset).objects.compact
    filter_visible_statuses(results)
  rescue Faraday::ConnectionFailed, Parslet::ParseFailed
    []
  end

  def local_status_search_results
    # Local-only status search is kept here for later use, but the current
    # SearchService gate does not call into it while profile-only search is active.
    return local_status_search_results_from_database unless Chewy.enabled?

    request             = parsed_query.request
    collected           = []
    remaining_offset    = @offset
    raw_offset          = 0
    window_size         = [@limit * 3, LOCAL_SEARCH_WINDOW].max

    loop do
      batch = request.collapse(field: :id).order(id: { order: :desc }).limit(window_size).offset(raw_offset).objects.compact
      break if batch.empty?

      visible_batch = filter_visible_statuses(batch.select(&:local?))
      visible_count = visible_batch.length

      if remaining_offset.positive?
        visible_batch = visible_batch.drop(remaining_offset)
        remaining_offset = [remaining_offset - visible_count, 0].max
      end

      collected.concat(visible_batch)
      break if collected.length >= @limit

      raw_offset += window_size
    end

    collected.take(@limit)
  rescue Faraday::ConnectionFailed, Parslet::ParseFailed
    []
  end

  def local_status_search_results_from_database
    collected        = []
    remaining_offset = @offset
    raw_offset       = 0
    window_size      = [@limit * 3, LOCAL_SEARCH_WINDOW].max

    loop do
      batch = database_local_status_scope.limit(window_size).offset(raw_offset).to_a
      break if batch.empty?

      visible_batch = filter_visible_statuses(batch)
      visible_count = visible_batch.length

      if remaining_offset.positive?
        visible_batch = visible_batch.drop(remaining_offset)
        remaining_offset = [remaining_offset - visible_count, 0].max
      end

      collected.concat(visible_batch)
      break if collected.length >= @limit

      raw_offset += window_size
    end

    collected.take(@limit)
  end

  def parsed_query
    SearchQueryTransformer.new.apply(SearchQueryParser.new.parse(@query), current_account: @account)
  end

  def convert_deprecated_options!
    syntax_options = []

    if @options[:account_id]
      username = Account.select(:username, :domain).find(@options[:account_id]).acct
      syntax_options << "from:@#{username}"
    end

    if @options[:min_id]
      timestamp = Mastodon::Snowflake.to_time(@options[:min_id].to_i)
      syntax_options << "after:\"#{timestamp.iso8601}\""
    end

    if @options[:max_id]
      timestamp = Mastodon::Snowflake.to_time(@options[:max_id].to_i)
      syntax_options << "before:\"#{timestamp.iso8601}\""
    end

    @query = "#{@query} #{syntax_options.join(' ')}".strip if syntax_options.any?
  end

  def filter_visible_statuses(results)
    account_ids         = results.map(&:account_id)
    account_domains     = results.map(&:account_domain)
    preloaded_relations = @account.relations_map(account_ids, account_domains)

    results.reject { |status| StatusFilter.new(status, @account, preloaded_relations).filtered? }
  end

  def database_local_status_scope
    Status
      .joins(:account)
      .includes(:status_stat, :account)
      .merge(Account.local.without_suspended)
      .without_reblogs
      .where(local: true, visibility: %i(public unlisted))
      .where(database_local_status_match_sql, query: @query)
      .reorder(id: :desc)
  end

  def database_local_status_match_sql
    <<~SQL.squish
      to_tsvector(
        'simple',
        coalesce(statuses.spoiler_text, '') || ' ' || coalesce(statuses.text, '')
      ) @@ websearch_to_tsquery('simple', :query)
    SQL
  end
end
