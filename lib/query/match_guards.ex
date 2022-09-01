defmodule ActiveMemory.Query.MatchGuards do
  @moduledoc false

  def build(table, query_map) do
    table.__attributes__(:query_fields)
    |> validate_query(query_map)
    |> build_match_tuple(query_map)
  end

  defp validate_query(attributes, query_map) do
    case Enum.all?(query_map, fn {key, _value} -> Enum.member?(attributes, key) end) do
      true -> {:ok, attributes}
      false -> {:error, :query_schema_mismatch}
    end
  end

  defp build_match_tuple({:ok, attributes}, query_map) do
    query =
      attributes
      |> Enum.into([], fn key -> Map.get(query_map, key, :_) end)
      |> List.to_tuple()

    {:ok, query}
  end

  defp build_match_tuple(error, _keywords), do: error
end
