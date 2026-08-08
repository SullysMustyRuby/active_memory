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

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [repo: :keep, min_ratio: :integer, max_rows: :integer],
        aliases: [r: :repo]
      )

    repo = resolve_repo(args)
    ensure_started(repo)
    adapter = repo.__adapter__()

    case Candidates.sql_for(adapter) do
      {:ok, sql} ->
        result = repo.query!(sql)

        result.rows
        |> Candidates.analyze(Keyword.take(opts, [:min_ratio, :max_rows]))
        |> Candidates.render()
        |> Mix.shell().info()

        Mix.shell().info(stats_window_note(repo, adapter))

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

  # `app.start` boots a supervised repo; a repo outside the supervision tree
  # (scripts, some release setups) still needs starting to be queried.
  defp ensure_started(repo) do
    case repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, error} -> Mix.raise("could not start #{inspect(repo)}: #{inspect(error)}")
    end
  end

  # Cumulative statistics only mean something over a known window, so tell the
  # reader when theirs began. Postgres records a reset time (NULL when the
  # statistics have never been reset); MySQL counters start at server start.
  defp stats_window_note(repo, Ecto.Adapters.Postgres) do
    case repo.query!(
           "SELECT stats_reset FROM pg_stat_database WHERE datname = current_database()"
         ) do
      %{rows: [[%DateTime{} = reset]]} ->
        "Statistics are cumulative since #{DateTime.to_iso8601(reset)}. " <>
          "Run against production-like traffic for meaningful ratios."

      _never_reset ->
        "Statistics are cumulative since this database's statistics began. " <>
          "Run against production-like traffic for meaningful ratios."
    end
  end

  defp stats_window_note(_repo, _adapter) do
    "Statistics are cumulative since the database server started. " <>
      "Run against production-like traffic for meaningful ratios."
  end
end
