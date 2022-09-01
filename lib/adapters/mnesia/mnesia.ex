defmodule ActiveMemory.Adapters.Mnesia do
  @moduledoc false

  alias ActiveMemory.Adapter
  alias ActiveMemory.Adapters.Mnesia.Helpers
  alias ActiveMemory.Query.{MatchGuards, MatchSpec}

  @behaviour Adapter

  def all(table) do
    case match_object(:mnesia.table_info(table, :wild_pattern)) do
      {:atomic, []} -> []
      {:atomic, records} -> Enum.into(records, [], &to_struct(&1, table))
      {:error, message} -> {:error, message}
    end
  end

  def create_table(table, _options) do
    options =
      [attributes: table.__attributes__(:query_fields)]
      |> Keyword.merge(table.__attributes__(:table_options))

    case :mnesia.create_table(table, options) do
      {:atomic, :ok} ->
        :mnesia.wait_for_tables([table], 5000)

      {:aborted, {:already_exists, _table}} ->
        copy_table(table)

      {:aborted, {:already_exists, _table, _node}} ->
        copy_table(table)

      {:error, message} ->
        {:error, message}
    end
  end

  def delete(struct, table) do
    case delete_object(struct, table) do
      {:atomic, :ok} -> :ok
      {:error, message} -> {:error, message}
    end
  end

  def delete_all(table) do
    :mnesia.clear_table(table)
  end

  def one(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         match_query <- Tuple.insert_at(query, 0, table),
         {:atomic, record} when length(record) == 1 <- match_object(match_query) do
      {:ok, to_struct(hd(record), table)}
    else
      {:atomic, []} -> {:ok, nil}
      {:atomic, records} when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def one(query, table) when is_tuple(query) do
    with match_spec = build_mnesia_match_spec(query, table),
         {:atomic, record} when length(record) == 1 <- select_object(match_spec, table) do
      {:ok, to_struct(hd(record), table)}
    else
      {:atomic, []} -> {:ok, nil}
      {:atomic, records} when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def select(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         match_query <- Tuple.insert_at(query, 0, table),
         {:atomic, records} when is_list(records) <- match_object(match_query) do
      {:ok, to_struct(records, table)}
    else
      {:atomic, []} -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def select(query, table) when is_tuple(query) do
    with match_spec = build_mnesia_match_spec(query, table),
         {:atomic, records} when records != [] <- select_object(match_spec, table) do
      {:ok, to_struct(records, table)}
    else
      {:atomic, []} -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def write(struct, table) do
    case write_object(to_tuple(struct), table) do
      {:atomic, :ok} -> {:ok, struct}
      {:error, message} -> {:error, message}
    end
  end

  defp copy_table(table) do
    case :mnesia.add_table_copy(table, Node.self(), :ram_copies) do
      {:atomic, :ok} ->
        :mnesia.wait_for_tables([table], 5000)

      {:aborted, {:already_exists, _table, _node}} ->
        :ok

      {:error, message} ->
        {:error, message}
    end
  end

  defp delete_object(struct, table) do
    :mnesia.transaction(fn ->
      :mnesia.delete_object(table, to_tuple(struct), :write)
    end)
  end

  defp match_object(query) do
    :mnesia.transaction(fn ->
      :mnesia.match_object(query)
    end)
  end

  defp select_object(match_spec, table) do
    :mnesia.transaction(fn ->
      :mnesia.select(table, match_spec, :read)
    end)
  end

  defp write_object(object, table) do
    :mnesia.transaction(fn ->
      :mnesia.write(table, object, :write)
    end)
  end

  defp build_mnesia_match_spec(query, table) do
    query_map = :erlang.apply(table, :__attributes__, [:query_map])
    match_head = :erlang.apply(table, :__attributes__, [:match_head])

    MatchSpec.build(query, query_map, match_head)
  end

  defp to_struct(records, table) when is_list(records) do
    Enum.into(records, [], &to_struct(&1, table))
  end

  defp to_struct(record, table) when is_tuple(record),
    do: Helpers.to_struct(record, table)

  defp to_tuple(struct), do: Helpers.to_tuple(struct)
end
