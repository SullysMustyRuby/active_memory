defmodule ActiveMemory.Candidates do
  @moduledoc """
  Finds database tables whose workload — read constantly, written rarely — makes
  them candidates for an `ActiveMemory.Table`.

  This is the engine behind `mix active_memory.candidates`, which runs it against
  the host application's own Ecto repo. The analysis itself is pure, so it can also
  be fed rows gathered any other way.

  ## The heuristic

  A table is a candidate when its **read/write ratio** is high and it is **small
  enough** to hold in memory. Reads and writes come from the database's own
  statistics:

    - PostgreSQL: `pg_stat_user_tables` — reads are scans (`seq_scan + idx_scan`,
      each query touching the table counts once), writes are rows changed
      (`n_tup_ins + n_tup_upd + n_tup_del`).
    - MySQL/MariaDB: `performance_schema.table_io_waits_summary_by_table` — reads
      are row fetch operations (`COUNT_FETCH`), writes are row change operations
      (`COUNT_INSERT + COUNT_UPDATE + COUNT_DELETE`).

  The two databases count reads differently (queries vs rows), so ratios are not
  comparable across databases — only between tables of the same one, which is what
  matters for finding candidates.

  Statistics are cumulative: since the last statistics reset on PostgreSQL, and
  since server start on MySQL. Run against a database that has seen
  production-like traffic, or the ratios describe nothing.
  """

  defstruct [:table, :rows, :bytes, :reads, :writes, :ratio, :verdict]

  @type t :: %__MODULE__{
          table: String.t(),
          rows: non_neg_integer(),
          bytes: non_neg_integer(),
          reads: non_neg_integer(),
          writes: non_neg_integer(),
          ratio: float() | :infinity,
          verdict:
            :strong | :candidate | :too_large | :write_heavy | :infrastructure | :no_traffic
        }

  @default_min_ratio 10
  @default_max_rows 50_000
  @default_min_reads 100

  @postgres_sql """
  SELECT relname,
         COALESCE(n_live_tup, 0),
         COALESCE(pg_total_relation_size(relid), 0),
         COALESCE(seq_scan, 0) + COALESCE(idx_scan, 0),
         COALESCE(n_tup_ins, 0) + COALESCE(n_tup_upd, 0) + COALESCE(n_tup_del, 0)
  FROM pg_stat_user_tables
  ORDER BY 4 DESC
  """

  @mysql_sql """
  SELECT io.OBJECT_NAME,
         COALESCE(t.TABLE_ROWS, 0),
         COALESCE(t.DATA_LENGTH + t.INDEX_LENGTH, 0),
         io.COUNT_FETCH,
         io.COUNT_INSERT + io.COUNT_UPDATE + io.COUNT_DELETE
  FROM performance_schema.table_io_waits_summary_by_table io
  LEFT JOIN information_schema.TABLES t
    ON t.TABLE_SCHEMA = io.OBJECT_SCHEMA AND t.TABLE_NAME = io.OBJECT_NAME
  WHERE io.OBJECT_SCHEMA = DATABASE()
  ORDER BY 4 DESC
  """

  @doc """
  The statistics query for an Ecto adapter.

  Returns `{:ok, sql}` whose result rows are
  `[table, row_estimate, total_bytes, reads, writes]`, or `{:error, message}` for
  an adapter without table-level read/write statistics.
  """
  @spec sql_for(module()) :: {:ok, String.t()} | {:error, String.t()}
  def sql_for(Ecto.Adapters.Postgres), do: {:ok, @postgres_sql}

  def sql_for(Ecto.Adapters.MyXQL), do: {:ok, @mysql_sql}

  def sql_for(adapter) do
    {:error,
     "#{inspect(adapter)} is not supported: only PostgreSQL and MySQL/MariaDB expose " <>
       "the table level read/write statistics this analysis needs."}
  end

  @doc """
  Classify raw statistics rows (`[table, rows, bytes, reads, writes]`).

  Options:
    - `:min_ratio` — reads per write to call a table a candidate
      (default #{@default_min_ratio}; ten times that is a strong candidate)
    - `:max_rows` — above this a table is `:too_large` for the in-memory sweet
      spot regardless of its ratio (default #{@default_max_rows})
    - `:min_reads` — below this many total operations a table's ratio carries no
      signal (one stray read of an untouched table is an infinite ratio), so it
      is reported as having too little traffic to judge
      (default #{@default_min_reads})

  Results are sorted candidates first, then by reads.
  """
  @spec analyze(list(list()), keyword()) :: list(t())
  def analyze(rows, opts \\ []) do
    min_ratio = Keyword.get(opts, :min_ratio, @default_min_ratio)
    max_rows = Keyword.get(opts, :max_rows, @default_max_rows)
    min_reads = Keyword.get(opts, :min_reads, @default_min_reads)

    rows
    |> Enum.map(fn [table, row_count, bytes, reads, writes] ->
      row_count = to_int(row_count)
      bytes = to_int(bytes)
      reads = to_int(reads)
      writes = to_int(writes)
      ratio = ratio(reads, writes)

      %__MODULE__{
        table: to_string(table),
        rows: row_count,
        bytes: bytes,
        reads: reads,
        writes: writes,
        ratio: ratio,
        verdict:
          verdict(
            to_string(table),
            ratio,
            row_count,
            reads,
            writes,
            {min_ratio, max_rows, min_reads}
          )
      }
    end)
    |> Enum.sort_by(fn %{verdict: verdict, reads: reads} -> {rank(verdict), -reads} end)
  end

  # Postgres returns these columns as integers, but MySQL promotes sums of its
  # unsigned bigint counters to DECIMAL, so MyXQL delivers Decimal structs.
  defp to_int(%Decimal{} = decimal), do: decimal |> Decimal.round(0) |> Decimal.to_integer()
  defp to_int(integer) when is_integer(integer), do: integer
  defp to_int(float) when is_float(float), do: round(float)
  defp to_int(nil), do: 0

  @doc """
  Render analyzed results as a text report.
  """
  @spec render(list(t())) :: String.t()
  def render([]), do: "No user tables with statistics found.\n"

  def render(results) do
    headers = ["table", "rows", "size", "reads", "writes", "ratio", "verdict"]

    rows =
      Enum.map(results, fn result ->
        [
          result.table,
          format_count(result.rows),
          format_bytes(result.bytes),
          format_count(result.reads),
          format_count(result.writes),
          format_ratio(result.ratio),
          label(result.verdict)
        ]
      end)

    widths =
      [headers | rows]
      |> Enum.zip_with(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    line = fn cells ->
      cells
      |> Enum.zip_with(widths, &String.pad_trailing/2)
      |> Enum.join("  ")
      |> String.trim_trailing()
    end

    candidates = Enum.count(results, &(&1.verdict in [:strong, :candidate]))

    summary =
      case candidates do
        0 -> "No candidates found with the current thresholds."
        1 -> "1 candidate for ActiveMemory."
        n -> "#{n} candidates for ActiveMemory."
      end

    Enum.join(
      [line.(headers), String.duplicate("-", Enum.sum(widths) + 2 * (length(widths) - 1))] ++
        Enum.map(rows, line) ++ ["", summary],
      "\n"
    ) <> "\n"
  end

  defp ratio(0, _writes), do: 0.0
  defp ratio(_reads, 0), do: :infinity
  defp ratio(reads, writes), do: reads / writes

  # Job queues and migration bookkeeping can look read-heavy — a queue poller
  # reads constantly, and an idle database shows no enqueues — but they are the
  # database's working state, not data an application should pin in memory.
  @infrastructure [~r/^oban_/, ~r/schema_migrations$/, ~r/^ar_internal_metadata$/]

  defp infrastructure?(table), do: Enum.any?(@infrastructure, &Regex.match?(&1, table))

  defp verdict(table, ratio, rows, reads, writes, {min_ratio, max_rows, min_reads}) do
    cond do
      infrastructure?(table) -> :infrastructure
      reads + writes < min_reads -> :no_traffic
      rows > max_rows -> :too_large
      ratio == :infinity -> :strong
      ratio >= min_ratio * 10 -> :strong
      ratio >= min_ratio -> :candidate
      true -> :write_heavy
    end
  end

  defp rank(:strong), do: 0
  defp rank(:candidate), do: 1
  defp rank(:too_large), do: 2
  defp rank(:write_heavy), do: 3
  defp rank(:infrastructure), do: 4
  defp rank(:no_traffic), do: 5

  defp label(:strong), do: "** strong candidate"
  defp label(:candidate), do: "*  candidate"
  defp label(:too_large), do: "too large to pin in memory"
  defp label(:write_heavy), do: "write heavy"
  defp label(:infrastructure), do: "infrastructure (queue/migrations)"
  defp label(:no_traffic), do: "not enough traffic to judge"

  defp format_ratio(:infinity), do: "inf"
  defp format_ratio(ratio) when ratio >= 100, do: "#{round(ratio)}:1"
  defp format_ratio(ratio), do: "#{Float.round(ratio * 1.0, 1)}:1"

  defp format_count(count) when count < 1000, do: Integer.to_string(count)

  defp format_count(count) do
    count
    |> Integer.to_string()
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{div(bytes, 1024 * 1024)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
