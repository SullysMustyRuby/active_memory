defmodule ActiveMemory.Adapters.Ets do
  alias ActiveMemory.{Adapter, MatchGuards, MatchSpec}
  @behaviour Adapter

  def all(table) do
    :ets.tab2list(table)
    |> Task.async_stream(fn record -> :erlang.apply(table, :to_struct, [record]) end)
    |> Enum.into([], fn {:ok, struct} -> struct end)
  end

  def create_table(table, _options) do
    :ets.new(table, [:named_table, :public, read_concurrency: true])
  end

  def delete(struct, table) do
    with ets_tuple when is_tuple(ets_tuple) <-
           :erlang.apply(table, :to_tuple, [struct]),
         true <- :ets.delete_object(table, ets_tuple) do
      :ok
    else
      _ -> {:error, :delete_failure}
    end
  end

  def delete_all(table) do
    :ets.delete_all_objects(table)
  end

  def one(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         [record | []] when is_tuple(record) <- match_query(query, table) do
      {:ok, to_struct(record, table)}
    else
      [] -> {:ok, nil}
      records when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def one(query, table) when is_tuple(query) do
    with [record | []] when is_tuple(record) <- select_query(query, table) do
      {:ok, to_struct(record, table)}
    else
      [] -> {:ok, nil}
      records when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def select(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         records when is_list(records) <- match_query(query, table) do
      {:ok, to_struct(records, table)}
    else
      [] -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def select(query, table) when is_tuple(query) do
    with records when is_list(records) <- select_query(query, table) do
      {:ok, to_struct(records, table)}
    else
      [] -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def write(struct, table) do
    with ets_tuple when is_tuple(ets_tuple) <-
           :erlang.apply(table, :to_tuple, [struct]),
         true <- :ets.insert(table, ets_tuple) do
      {:ok, struct}
    else
      false -> {:error, :write_fail}
      {:error, message} -> {:error, message}
    end
  end

  defp match_query(query, table) do
    :ets.match_object(table, query)
  end

  defp select_query(query, table) do
    match_query = MatchSpec.build(query, table)
    :ets.select(table, match_query)
  end

  defp to_struct(records, table) when is_list(records) do
    Enum.into(records, [], fn record -> to_struct(record, table) end)
  end

  defp to_struct(record, table) when is_tuple(record) do
    :erlang.apply(table, :to_struct, [record])
  end
end
