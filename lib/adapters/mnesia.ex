defmodule ActiveMemory.Adapters.Mnesia do
  alias ActiveMemory.Adapter
  alias ActiveMemory.Adapter.Helpers
  alias ActiveMemory.Query.{MatchGuards, MatchSpec}

  @behaviour Adapter

  def all(table) do
    case match_object(:mnesia.table_info(table, :wild_pattern)) do
      {:atomic, []} -> []
      {:atomic, records} -> Enum.into(records, [], &convert_to_struct(&1, table))
      {:error, message} -> {:error, message}
    end
  end

  def copy_table(table) do
    case :mnesia.add_table_copy(table, Node.self(), :ram_copies) do
      {:atomic, :ok} ->
        :ok

      {:error, message} ->
        {:error, message}
    end
  end

  def create_table(table, _options) do
    options = [{:ram_copies, [node()]}, attributes: table.__meta__.attributes]

    case :mnesia.create_table(table, options) do
      {:atomic, :ok} ->
        :ok

      {:error, {:already_exists, _table}} ->
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
      {:ok, convert_to_struct(hd(record), table)}
    else
      {:atomic, []} -> {:ok, nil}
      {:atomic, records} when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def one(query, table) when is_tuple(query) do
    with match_spec = build_mnesia_match_spec(query, table),
         {:atomic, record} when length(record) == 1 <- select_object(match_spec, table) do
      {:ok, convert_to_struct(hd(record), table)}
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
      {:ok, Enum.into(records, [], &convert_to_struct(&1, table))}
    else
      {:atomic, []} -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def select(query, table) when is_tuple(query) do
    with match_spec = build_mnesia_match_spec(query, table),
         {:atomic, records} when records != [] <- select_object(match_spec, table) do
      {:ok, Enum.into(records, [], &convert_to_struct(&1, table))}
    else
      {:atomic, []} -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def write(struct, table) do
    case write_object(convert_from_struct(struct), table) do
      {:atomic, :ok} -> {:ok, struct}
      {:error, message} -> {:error, message}
    end
  end

  defp delete_object(struct, table) do
    :mnesia.transaction(fn ->
      :mnesia.delete_object(table, convert_from_struct(struct), :write)
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
    [{match_head, query, result}] = MatchSpec.build(query, table)
    [{Tuple.insert_at(match_head, 0, table), query, result}]
  end

  defp convert_to_struct(object, table) do
    object
    |> Tuple.delete_at(0)
    |> Helpers.to_struct(table)
  end

  defp convert_from_struct(%{__struct__: name} = struct) do
    struct
    |> Helpers.to_tuple()
    |> Tuple.insert_at(0, name)
  end
end
