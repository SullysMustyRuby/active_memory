defmodule ActiveMemory.NotFoundError do
  @moduledoc """
  Raised by the bang variants of the read functions (`get!/1`, `get_by!/1`,
  `one!/1`, `reload!/1`) when no record matches.

  The non-bang variants return `{:error, :not_found}` instead. Mirrors
  `Ecto.NoResultsError`.
  """

  defexception [:message, :table, :query]

  @impl true
  def exception(opts) do
    table = Keyword.fetch!(opts, :table)
    query = Keyword.get(opts, :query)

    %__MODULE__{
      message: "no record found in #{inspect(table)} matching #{inspect(query)}",
      table: table,
      query: query
    }
  end
end

defmodule ActiveMemory.MultipleResultsError do
  @moduledoc """
  Raised by `one/1`, `one!/1`, `get_by/1` and `get_by!/1` when a query intended to
  match a single record matches more than one.

  Use `select/1` when many records are expected. Mirrors
  `Ecto.MultipleResultsError`.
  """

  defexception [:message, :table, :query, :count]

  @impl true
  def exception(opts) do
    table = Keyword.fetch!(opts, :table)
    query = Keyword.get(opts, :query)
    count = Keyword.get(opts, :count)

    %__MODULE__{
      message:
        "expected at most one record in #{inspect(table)} matching #{inspect(query)} " <>
          "but got #{count || "several"}. Use select/1 when many records are expected.",
      table: table,
      query: query,
      count: count
    }
  end
end
