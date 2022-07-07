defmodule ActiveMemory.Adapters.Ets.Helpers do
  @moduledoc false

  @types [:set, :ordered_set, :bag, :duplicate_bag]
  @access [:public, :protected, :private]
  @default_options [type: :set, access: :public]

  def build_match_head(query_map) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
  end

  def build_options(:defaults), do: [:set, :public]

  def build_options(options) do
    @default_options
    |> Keyword.merge(options)
    |> Enum.into([], fn {key, value} -> validate_option(key, value) end)
    |> Enum.reject(&is_nil/1)
  end

  def to_struct(tuple, module) when is_tuple(tuple),
    do: struct(module, build_struct(module.__meta__.attributes, tuple))

  def to_tuple(%{__struct__: module} = struct) do
    module.__meta__.attributes
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
  end

  defp build_struct(attributes, tuple) do
    attributes
    |> Enum.with_index(fn element, index -> {element, elem(tuple, index)} end)
    |> Enum.into(%{})
  end

  defp validate_option(:type, type) do
    case Enum.member?(@types, type) do
      true -> type
      false -> hd(@types)
    end
  end

  defp validate_option(:access, access) do
    case Enum.member?(@access, access) do
      true -> access
      false -> hd(@access)
    end
  end

  defp validate_option(:decentralized_counters, true),
    do: {:decentralized_counters, true}

  defp validate_option(:compressed, true),
    do: :compressed

  defp validate_option(:read_concurrency, true),
    do: {:read_concurrency, true}

  defp validate_option(:write_concurrency, true),
    do: {:write_concurrency, true}

  defp validate_option(:write_concurrency, :auto),
    do: {:write_concurrency, :auto}

  defp validate_option(_key, _value), do: nil
end
