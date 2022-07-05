defmodule ActiveMemory.Adapters.Mnesia.Helpers do
  @default_options [{:ram_copies, [node()]}]

  def build_match_head(query_map, table_name) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, table_name)
  end

  def build_options(options) do
    @default_options
    # |> Keyword.merge(options)
    # |> validate_option([])
  end

  def to_struct(tuple, module) when is_tuple(tuple),
    do: struct(module, build_struct(module.__meta__.attributes, Tuple.delete_at(tuple, 0)))

  def to_tuple(%{__struct__: module} = struct) do
    module.__meta__.attributes
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, module)
  end

  defp build_struct(attributes, tuple) do
    attributes
    |> Enum.with_index(fn element, index -> {element, elem(tuple, index)} end)
    |> Enum.into(%{})
  end

  # defp validate_option([], options), do: options
end
