defmodule ActiveMemory.Definition do
  def set_adapter(:ets), do: ActiveMemory.Adapters.Ets

  def set_adapter(:mnesia), do: ActiveMemory.Adapters.Mnesia

  def build_match_head(query_map) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
  end

  def build_query_map(attributes) do
    Enum.with_index(attributes, fn element, index -> {element, :"$#{index + 1}"} end)
  end
end
