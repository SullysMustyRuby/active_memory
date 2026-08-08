defmodule ActiveMemory.CandidatesTest do
  use ExUnit.Case, async: true

  alias ActiveMemory.Candidates

  # The `plans`/`events` rows are verbatim from pg_stat_user_tables on a real
  # PostgreSQL 17 database after a simulated read-heavy/write-heavy workload.
  @plans ["plans", 20, 32_768, 501, 20]
  @events ["events", 2000, 278_528, 3, 3000]

  describe "analyze/2" do
    test "classifies a read-heavy table as a candidate and a write-heavy one as not" do
      assert [plans, events] = Candidates.analyze([@events, @plans])

      assert %{table: "plans", verdict: :candidate} = plans
      assert_in_delta plans.ratio, 25.05, 0.001

      assert %{table: "events", verdict: :write_heavy} = events
    end

    test "a table with reads and zero writes is a strong candidate with infinite ratio" do
      assert [%{verdict: :strong, ratio: :infinity}] =
               Candidates.analyze([["countries", 249, 65_536, 9000, 0]])
    end

    test "a ratio of at least ten times min_ratio is strong" do
      assert [%{verdict: :strong}] =
               Candidates.analyze([["flags", 12, 8192, 1000, 5]])
    end

    test "a large table is flagged regardless of its ratio" do
      assert [%{verdict: :too_large}] =
               Candidates.analyze([["users", 2_000_000, 1_073_741_824, 9_000_000, 10]])
    end

    test "max_rows and min_ratio are tunable" do
      assert [%{verdict: :strong}] =
               Candidates.analyze([["users", 2_000_000, 0, 9_000_000, 10]],
                 max_rows: 5_000_000,
                 min_ratio: 100
               )

      assert [%{verdict: :write_heavy}] = Candidates.analyze([@plans], min_ratio: 50)
    end

    test "a table with no traffic at all is reported as such, not as a candidate" do
      assert [%{verdict: :no_traffic}] =
               Candidates.analyze([["archived", 10, 8192, 0, 0]])
    end

    test "a stray read of an untouched table carries no signal" do
      # From a real dev database: one incidental read gives an infinite ratio,
      # which would have called 35 idle tables strong candidates.
      assert [%{verdict: :no_traffic}] =
               Candidates.analyze([["b4b_rentals", 0, 8192, 1, 0]])

      # tunable: with the floor lowered, the same table classifies on its ratio
      assert [%{verdict: :strong}] =
               Candidates.analyze([["b4b_rentals", 0, 8192, 1, 0]], min_reads: 1)
    end

    test "zero reads with some writes is write heavy, not a divide error" do
      assert [%{verdict: :write_heavy, ratio: +0.0}] =
               Candidates.analyze([["audit_log", 100, 8192, 0, 500]])
    end

    test "normalizes the Decimal values MyXQL returns for MySQL's counters" do
      # MySQL promotes sums of BIGINT UNSIGNED counters to DECIMAL, so every
      # numeric column can arrive as a Decimal rather than an integer. Shapes
      # taken from a run against a real Aurora MySQL staging database.
      rows = [
        [
          "accounts",
          Decimal.new(120),
          Decimal.new("221184"),
          Decimal.new("50000"),
          Decimal.new("3")
        ],
        ["events", Decimal.new(0), Decimal.new("0"), Decimal.new("0"), Decimal.new("0")]
      ]

      assert [accounts, events] = Candidates.analyze(rows)

      assert %{verdict: :strong, rows: 120, bytes: 221_184, reads: 50_000, writes: 3} = accounts
      assert %{verdict: :no_traffic} = events

      # rendering must not crash on the normalized values
      report = Candidates.render([accounts, events])
      assert report =~ "50,000"
      assert report =~ "216 KB"
    end

    test "queue and migration tables are infrastructure, not candidates" do
      # From a real staging run: an idle Oban polls its queue constantly and
      # enqueues nothing, which looks like a strong candidate by the numbers.
      rows = [
        ["oban_jobs", 0, 32_768, 31_329, 0],
        ["oban_peers", 1, 16_384, 2209, 1485],
        ["phoenix_schema_migrations", 7, 16_384, 35, 7]
      ]

      assert Enum.all?(Candidates.analyze(rows), &(&1.verdict == :infrastructure))
    end

    test "sorts candidates first, then by reads" do
      rows = [
        @events,
        ["countries", 249, 65_536, 900, 0],
        @plans,
        ["stale", 5, 8192, 0, 0]
      ]

      assert ["countries", "plans", "events", "stale"] =
               Candidates.analyze(rows) |> Enum.map(& &1.table)
    end
  end

  describe "render/1" do
    test "renders a table with a summary line" do
      report = Candidates.analyze([@plans, @events]) |> Candidates.render()

      assert report =~ "plans"
      assert report =~ "candidate"
      assert report =~ "25.1:1"
      assert report =~ "write heavy"
      assert report =~ "1 candidate for ActiveMemory."
    end

    test "formats large numbers, sizes, and infinite ratios readably" do
      report =
        Candidates.analyze([["countries", 249, 1_262_485_504, 1_234_567, 0]],
          max_rows: 500
        )
        |> Candidates.render()

      assert report =~ "1,234,567"
      assert report =~ "1.2 GB"
      assert report =~ "inf"
    end

    test "an empty result explains itself" do
      assert Candidates.render([]) =~ "No user tables"
    end
  end

  describe "sql_for/1" do
    test "supports postgres and mysql, rejects others by name" do
      assert {:ok, sql} = Candidates.sql_for(Ecto.Adapters.Postgres)
      assert sql =~ "pg_stat_user_tables"

      assert {:ok, sql} = Candidates.sql_for(Ecto.Adapters.MyXQL)
      assert sql =~ "performance_schema.table_io_waits_summary_by_table"

      assert {:error, message} = Candidates.sql_for(Ecto.Adapters.SQLite3)
      assert message =~ "SQLite3"
    end
  end
end
