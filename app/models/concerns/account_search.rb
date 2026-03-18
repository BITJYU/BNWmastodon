# frozen_string_literal: true

module AccountSearch
  extend ActiveSupport::Concern

  DISALLOWED_TSQUERY_CHARACTERS = /['?\\:‘’]/

  TEXT_SEARCH_RANKS = <<~SQL.squish
    (
        setweight(to_tsvector('simple', accounts.display_name), 'A') ||
        setweight(to_tsvector('simple', accounts.username), 'B') ||
        setweight(to_tsvector('simple', coalesce(accounts.domain, '')), 'C')
    )
  SQL

  REPUTATION_SCORE_FUNCTION = <<~SQL.squish
    (
        greatest(0, coalesce(s.followers_count, 0)) / (
            greatest(0, coalesce(s.following_count, 0)) + 1.0
        )
    )
  SQL

  FOLLOWERS_SCORE_FUNCTION = <<~SQL.squish
    log(
        greatest(0, coalesce(s.followers_count, 0)) + 2
    )
  SQL

  TIME_DISTANCE_FUNCTION = <<~SQL.squish
    (
        case
            when s.last_status_at is null then 0
            else exp(
                -1.0 * (
                    (
                        greatest(0, abs(extract(DAY FROM age(s.last_status_at))) - 30.0)^2) /#{' '}
                        (2.0 * ((-1.0 * 30^2) / (2.0 * ln(0.3)))
                    )
                )
            )
        end
    )
  SQL

  BOOST = <<~SQL.squish
    (
        (#{REPUTATION_SCORE_FUNCTION} + #{FOLLOWERS_SCORE_FUNCTION} + #{TIME_DISTANCE_FUNCTION}) / 3.0
    )
  SQL

  BASIC_SEARCH_SQL = <<~SQL.squish
    SELECT
      accounts.*,
      #{BOOST} * ts_rank_cd(#{TEXT_SEARCH_RANKS}, to_tsquery('simple', :tsquery), 32) AS rank
    FROM accounts
    LEFT JOIN users ON accounts.id = users.account_id
    LEFT JOIN account_stats AS s ON accounts.id = s.account_id
    WHERE to_tsquery('simple', :tsquery) @@ #{TEXT_SEARCH_RANKS}
      AND accounts.suspended_at IS NULL
      AND accounts.moved_to_account_id IS NULL
      AND (accounts.domain IS NOT NULL OR (users.approved = TRUE AND users.confirmed_at IS NOT NULL))
    ORDER BY rank DESC
    LIMIT :limit OFFSET :offset
  SQL

  ADVANCED_SEARCH_WITH_FOLLOWING = <<~SQL.squish
    WITH first_degree AS (
      SELECT target_account_id
      FROM follows
      WHERE account_id = :id
      UNION ALL
      SELECT :id
    )
    SELECT
      accounts.*,
      (count(f.id) + 1) * #{BOOST} * ts_rank_cd(#{TEXT_SEARCH_RANKS}, to_tsquery('simple', :tsquery), 32) AS rank
    FROM accounts
    LEFT OUTER JOIN follows AS f ON (accounts.id = f.account_id AND f.target_account_id = :id)
    LEFT JOIN account_stats AS s ON accounts.id = s.account_id
    WHERE accounts.id IN (SELECT * FROM first_degree)
      AND to_tsquery('simple', :tsquery) @@ #{TEXT_SEARCH_RANKS}
      AND accounts.suspended_at IS NULL
      AND accounts.moved_to_account_id IS NULL
    GROUP BY accounts.id, s.id
    ORDER BY rank DESC
    LIMIT :limit OFFSET :offset
  SQL

  ADVANCED_SEARCH_WITHOUT_FOLLOWING = <<~SQL.squish
    SELECT
      accounts.*,
      #{BOOST} * ts_rank_cd(#{TEXT_SEARCH_RANKS}, to_tsquery('simple', :tsquery), 32) AS rank,
      count(f.id) AS followed
    FROM accounts
    LEFT OUTER JOIN follows AS f ON
      (accounts.id = f.account_id AND f.target_account_id = :id) OR (accounts.id = f.target_account_id AND f.account_id = :id)
    LEFT JOIN users ON accounts.id = users.account_id
    LEFT JOIN account_stats AS s ON accounts.id = s.account_id
    WHERE to_tsquery('simple', :tsquery) @@ #{TEXT_SEARCH_RANKS}
      AND accounts.suspended_at IS NULL
      AND accounts.moved_to_account_id IS NULL
      AND (accounts.domain IS NOT NULL OR (users.approved = TRUE AND users.confirmed_at IS NOT NULL))
    GROUP BY accounts.id, s.id
    ORDER BY followed DESC, rank DESC
    LIMIT :limit OFFSET :offset
  SQL

  LOCAL_ONLY_SQL = 'AND accounts.domain IS NULL'

  def searchable_text
    PlainTextFormatter.new(note, local?).to_s if discoverable?
  end

  def searchable_properties
    [].tap do |properties|
      properties << 'bot' if bot?
      properties << 'verified' if fields.any?(&:verified?)
    end
  end

  class_methods do
    def search_for(terms, limit: 10, offset: 0, local_only: false)
      tsquery = generate_query_for_search(terms)

      find_by_sql([sql_for_basic_search(local_only: local_only), { limit: limit, offset: offset, tsquery: tsquery }]).tap do |records|
        ActiveRecord::Associations::Preloader.new(records: records, associations: :account_stat)
      end
    end

    def advanced_search_for(terms, account, limit: 10, following: false, offset: 0, local_only: false)
      tsquery = generate_query_for_search(terms)
      sql_template = following ? sql_for_advanced_search_with_following(local_only: local_only) : sql_for_advanced_search_without_following(local_only: local_only)

      find_by_sql([sql_template, { id: account.id, limit: limit, offset: offset, tsquery: tsquery }]).tap do |records|
        ActiveRecord::Associations::Preloader.new(records: records, associations: :account_stat)
      end
    end

    private

    def sql_for_basic_search(local_only: false)
      return BASIC_SEARCH_SQL unless local_only

      BASIC_SEARCH_SQL.sub('ORDER BY rank DESC', "#{LOCAL_ONLY_SQL}\n    ORDER BY rank DESC")
    end

    def sql_for_advanced_search_with_following(local_only: false)
      return ADVANCED_SEARCH_WITH_FOLLOWING unless local_only

      ADVANCED_SEARCH_WITH_FOLLOWING.sub('GROUP BY accounts.id, s.id', "#{LOCAL_ONLY_SQL}\n    GROUP BY accounts.id, s.id")
    end

    def sql_for_advanced_search_without_following(local_only: false)
      return ADVANCED_SEARCH_WITHOUT_FOLLOWING unless local_only

      ADVANCED_SEARCH_WITHOUT_FOLLOWING.sub('GROUP BY accounts.id, s.id', "#{LOCAL_ONLY_SQL}\n    GROUP BY accounts.id, s.id")
    end

    def generate_query_for_search(unsanitized_terms)
      terms = unsanitized_terms.gsub(DISALLOWED_TSQUERY_CHARACTERS, ' ')

      # The final ":*" is for prefix search.
      # The trailing space does not seem to fit any purpose, but `to_tsquery`
      # behaves differently with and without a leading space if the terms start
      # with `./`, `../`, or `.. `. I don't understand why, so, in doubt, keep
      # the same query.
      "' #{terms} ':*"
    end
  end
end
