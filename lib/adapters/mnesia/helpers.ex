defmodule ActiveMemory.Adapters.Mnesia.Helpers do
  @moduledoc false

  @types [:set, :ordered_set, :bag]

  def build_match_head(query_map, table_name) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, table_name)
  end

  def build_options(:defaults), do: []

  def build_options(options) do
    options
    |> Enum.into([], fn {key, value} -> validate_option(key, value) end)
    |> Enum.reject(&is_nil/1)
  end

  def to_struct(tuple, module) when is_tuple(tuple),
    do:
      struct(
        module,
        build_struct(module.__attributes__(:query_fields), Tuple.delete_at(tuple, 0))
      )

  def to_tuple(%{__struct__: module} = struct) do
    module.__attributes__(:query_fields)
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, module)
  end

  defp build_struct(attributes, tuple) do
    attributes
    |> Enum.with_index(fn element, index -> {element, elem(tuple, index)} end)
    |> Enum.into(%{})
  end

  defp validate_option(:access_mode, :read_only), do: {:access_mode, :read_only}

  defp validate_option(:access_mode, :read_write), do: {:access_mode, :read_write}

  defp validate_option(:disc_copies, node_list) when is_list(node_list),
    do: {:disc_copies, node_list}

  defp validate_option(:disc_only_copies, node_list) when is_list(node_list),
    do: {:disc_only_copies, node_list}

  defp validate_option(:index, index_list) when is_list(index_list),
    do: {:index, index_list}

  defp validate_option(:load_order, integer) when is_integer(integer) and integer >= 0,
    do: {:load_order, integer}

  defp validate_option(:majority, false), do: {:majority, false}

  defp validate_option(:majority, true), do: {:majority, true}

  defp validate_option(:ram_copies, node_list) when is_list(node_list),
    do: {:ram_copies, node_list}

  defp validate_option(:type, type) do
    case Enum.member?(@types, type) do
      true -> {:type, type}
      false -> {:type, hd(@types)}
    end
  end

  defp validate_option(_, _), do: nil
end
