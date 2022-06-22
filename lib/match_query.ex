defmodule MnesiaCompanion.MatchQuery do
  def build(table, query_map) do
    keywords = Map.to_list(query_map)

    table
    |> :mnesia.table_info(:attributes)
    |> validate_query(keywords)
    |> build_match_tuple(keywords)
  end

  defp validate_query(attributes, keywords) do
    case Enum.all?(keywords, fn {key, _value} -> Enum.member?(attributes, key) end) do
      true -> {:ok, attributes}
      false -> {:error, :query_schema_mismatch}
    end
  end

  defp build_match_tuple({:ok, attributes}, keywords) do
    attributes
    |> Enum.into([], fn key -> Keyword.get(keywords, key, :_) end)
    |> List.to_tuple()
  end

  defp build_match_tuple(error, _keywords), do: error
end
