defmodule Mix.Tasks.ActiveMemory.Candidates do
  @shortdoc "Find database tables that would benefit from ActiveMemory"

  @moduledoc """
  Reads your database's own table statistics through the application's Ecto repo
  and reports which tables have the high-read, low-write workload that makes them
  candidates for an `ActiveMemory.Table`.

      $ mix active_memory.candidates
      $ mix active_memory.candidates -r MyApp.Repo
      $ mix active_memory.candidates --min-ratio 25 --max-rows 10000

  The repo comes from `-r`/`--repo`, or from the application's `:ecto_repos`
  configuration, exactly as the `ecto.*` tasks resolve it. PostgreSQL and
  MySQL/MariaDB are supported; the statistics sources and what counts as a "read"
  on each are described in `ActiveMemory.Candidates`.

  ## Options

    * `-r`, `--repo` — the Ecto repo to read statistics through
    * `--min-ratio` — reads per write to call a table a candidate (default 10;
      ten times this is a strong candidate)
    * `--max-rows` — tables above this row count are flagged as too large for the
      in-memory sweet spot (default 50000)
    * `--min-reads` — tables with fewer total operations than this are reported
      as having too little traffic to judge, since a stray read of an untouched
      table would otherwise look infinitely read-heavy (default 100)
    * `--timeout` — query timeout in milliseconds, for schemas so large the
      statistics views themselves are slow (default is the repo's own timeout)

  ## Safe against production

  The task performs only read-only queries against the database's statistics
  views — it never touches application tables — and it does **not** start your
  application: only its configuration is loaded, and the one repo you name is
  started with a two connection pool. Nothing else connects: no other repos, no
  job processors, no endpoints. Use read-only credentials anyway; they cost
  nothing. The expected impact is the connections themselves plus a few
  statistics queries.

  ## Reading the report

  Statistics are cumulative — since the last statistics reset on PostgreSQL, since
  server start on MySQL — so run this against a database that has seen
  production-like traffic. A development database exercised only by your test
  suite will tell you nothing useful.

  A candidate is worth confirming by eye: the numbers say "read constantly,
  written rarely", but only you know whether the table is authoritative data your
  application could load at boot and serve from memory.
  """

  use Mix.Task

  alias ActiveMemory.Candidates

  # Deliberately `app.config`, not `app.start`: the application is NOT booted,
  # only its configuration is loaded and the one repo is started. Pointing this
  # task at a production database must not also point Oban, background jobs and
  # every other repo pool at it.
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          repo: :keep,
          min_ratio: :integer,
          max_rows: :integer,
          min_reads: :integer,
          timeout: :integer
        ],
        aliases: [r: :repo]
      )

    repo = resolve_repo(args)
    ensure_started(repo)
    adapter = repo.__adapter__()

    query_opts = [log: false] ++ Keyword.take(opts, [:timeout])

    case Candidates.sql_for(adapter) do
      {:ok, sql} ->
        result = repo.query!(sql, [], query_opts)

        result.rows
        |> Candidates.analyze(Keyword.take(opts, [:min_ratio, :max_rows, :min_reads]))
        |> Candidates.render()
        |> Mix.shell().info()

        Mix.shell().info(stats_window_note(repo, adapter, query_opts))

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp resolve_repo(args) do
    case Mix.Ecto.parse_repo(args) do
      [repo | _rest] ->
        Mix.Ecto.ensure_repo(repo, args)

      [] ->
        Mix.raise(
          "no Ecto repo found. Pass one with -r MyApp.Repo or configure :ecto_repos " <>
            "for your application."
        )
    end
  end

  # The application is not started, so the adapter's applications (postgrex or
  # myxql, db_connection) and the repo itself are started here, with a minimal
  # pool. `already_started` is tolerated for callers running inside an app.
  defp ensure_started(repo) do
    # :ecto runs the Repo.Registry every repo registers with on start
    {:ok, _ecto} = Application.ensure_all_started(:ecto)
    {:ok, _apps} = repo.__adapter__().ensure_all_started(repo.config(), :temporary)

    case repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, error} -> Mix.raise("could not start #{inspect(repo)}: #{inspect(error)}")
    end
  end

  # Cumulative statistics only mean something over a known window, so tell the
  # reader when theirs began. Postgres records a reset time (NULL when the
  # statistics have never been reset); MySQL counters start at server start.
  defp stats_window_note(repo, Ecto.Adapters.Postgres, query_opts) do
    case repo.query!(
           "SELECT stats_reset FROM pg_stat_database WHERE datname = current_database()",
           [],
           query_opts
         ) do
      %{rows: [[%DateTime{} = reset]]} ->
        "Statistics are cumulative since #{DateTime.to_iso8601(reset)}. " <>
          "Run against production-like traffic for meaningful ratios."

      _never_reset ->
        "Statistics are cumulative since this database's statistics began. " <>
          "Run against production-like traffic for meaningful ratios."
    end
  end

  defp stats_window_note(_repo, _adapter, _query_opts) do
    "Statistics are cumulative since the database server started. " <>
      "Run against production-like traffic for meaningful ratios."
  end
end
