defmodule ActiveMemory.Definition do
  alias ActiveMemory.Adapters.{Ets, Mnesia}

  def set_adapter(:ets), do: Ets

  def set_adapter(:mnesia), do: Mnesia

  def build_ets_match_head(query_map, _table_name) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
  end

  def build_mnesia_match_head(query_map, table_name) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, table_name)
  end

  def build_query_map(struct_attrs) do
    Enum.with_index(struct_attrs, fn element, index ->
      {strip_defaults(element), :"$#{index + 1}"}
    end)
  end

  def build_struct_keys(struct_attrs) do
    Enum.into(struct_attrs, [], fn element -> strip_defaults(element) end)
  end

  defp strip_defaults(element) when is_atom(element), do: element

  defp strip_defaults({element, _defaults}) when is_atom(element), do: element
end
