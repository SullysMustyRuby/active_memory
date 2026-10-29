defmodule ActiveMemory.Adapters.Ets.Helpers do
  @moduledoc false

  @access [:public, :protected, :private]
  @default_options [type: :set, access: :public]
  # ActiveMemory names the table, keys it on the first field and assigns its heir.
  @owned_options [:heir, :keypos, :named_table]
  @supported_options [
    :access,
    :compressed,
    :decentralized_counters,
    :read_concurrency,
    :type,
    :write_concurrency
  ]
  @types [:set, :ordered_set, :bag, :duplicate_bag]

  @spec build_match_head(list()) :: tuple()
  def build_match_head(query_map) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
  end

  @spec build_options(atom() | list()) :: list()
  def build_options(:defaults), do: [:set, :public]

  def build_options(options) do
    case Keyword.keyword?(options) do
      true ->
        @default_options
        |> Keyword.merge(options)
        |> Enum.map(fn {key, value} -> validate_option(key, value) end)
        |> Enum.reject(&is_nil/1)

      false ->
        raise ArgumentError, "ETS table options must be a keyword list, got: #{inspect(options)}"
    end
  end

  @spec to_struct(tuple(), atom()) :: map()
  def to_struct(tuple, module) when is_tuple(tuple),
    do: struct(module, build_struct(module.__attributes__(:query_fields), tuple))

  @spec to_tuple(map()) :: tuple()
  def to_tuple(%{__struct__: module} = struct) do
    module.__attributes__(:query_fields)
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
  end

  defp build_struct(attributes, tuple) do
    attributes
    |> Enum.with_index(fn element, index -> {element, elem(tuple, index)} end)
    |> Enum.into(%{})
  end

  defp invalid_option!(key, _value) when key in @owned_options,
    do: raise(ArgumentError, "the ETS table option #{inspect(key)} is set by ActiveMemory")

  defp invalid_option!(key, value) when key in @supported_options,
    do:
      raise(
        ArgumentError,
        "invalid value #{inspect(value)} for the ETS table option #{inspect(key)}"
      )

  defp invalid_option!(key, _value) do
    raise ArgumentError,
          "unknown ETS table option #{inspect(key)}, expected one of #{inspect(@supported_options)}"
  end

  defp validate_option(:access, access) when access in @access, do: access

  defp validate_option(:compressed, true), do: :compressed

  defp validate_option(:compressed, false), do: nil

  defp validate_option(:decentralized_counters, value) when is_boolean(value),
    do: {:decentralized_counters, value}

  defp validate_option(:read_concurrency, value) when is_boolean(value),
    do: {:read_concurrency, value}

  defp validate_option(:type, type) when type in @types, do: type

  defp validate_option(:write_concurrency, value) when is_boolean(value) or value == :auto,
    do: {:write_concurrency, value}

  defp validate_option(key, value), do: invalid_option!(key, value)
end
