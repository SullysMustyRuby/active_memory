defmodule ActiveMemory.Mnesia.Adapter do
  alias ActiveMemory.MatchGuards

  def all_records(table) do
    Memento.transaction!(fn ->
      Memento.Query.all(table)
    end)
  end

  def delete(struct, table) do
    Memento.transaction!(fn ->
      Memento.Query.delete_record(struct)
    end)
  end

  def delete_all(table) do
    :mnesia.clear_table(table)
  end

  def create_table(table) do
    Memento.Table.create!(table)
  end

  def one(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         {:ok, [record | []]} <- match_query(query, table) do
      {:ok, record}
    else
      {:ok, []} -> {:ok, nil}
      {:ok, records} when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def one(query, table) when is_tuple(query) do
    case select_query(query, table) do
      {:ok, [record | []]} -> {:ok, record}
      {:ok, []} -> {:ok, nil}
      {:ok, records} when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def select(query_map, table) when is_map(query_map) do
    case MatchGuards.build(table, query_map) do
      {:ok, query} ->
        match_query(query, table)

      {:error, message} ->
        {:error, message}
    end
  end

  def select(query, table) when is_tuple(query) do
    select_query(query, table)
  end

  def withdraw(query, table) do
    with {:ok, %{} = record} <- one(query, table),
         :ok <- delete(record, table) do
      {:ok, record}
    else
      {:ok, nil} -> {:ok, nil}
      {:error, message} -> {:error, message}
    end
  end

  def write(struct, _table) do
    Memento.transaction(fn ->
      Memento.Query.write(struct)
    end)
  end

  defp match_query(query, table) do
    Memento.transaction(fn ->
      Memento.Query.match(table, query)
    end)
  end

  defp select_query(query, table) do
    Memento.transaction(fn ->
      Memento.Query.select(table, query)
    end)
  end
end
