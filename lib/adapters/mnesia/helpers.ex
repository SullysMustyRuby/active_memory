defmodule ActiveMemory.Adapters.Mnesia.Helpers do
  @moduledoc false

  # ActiveMemory sets the record name and attributes from the table module's fields.
  @owned_options [:attributes, :record_name]
  @supported_options [
    :access_mode,
    :disc_copies,
    :disc_only_copies,
    :index,
    :load_order,
    :local_content,
    :majority,
    :ram_copies,
    :storage_properties,
    :type,
    :user_properties
  ]
  @types [:set, :ordered_set, :bag]

  @spec build_match_head(list(), atom()) :: tuple()
  def build_match_head(query_map, table_name) do
    query_map
    |> Enum.into([], fn {_key, value} -> value end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, table_name)
  end

  @spec build_options(atom() | list()) :: list()
  def build_options(:defaults), do: []

  def build_options(options) do
    case Keyword.keyword?(options) do
      true ->
        Enum.map(options, fn {key, value} -> validate_option(key, value) end)

      false ->
        raise ArgumentError,
              "Mnesia table options must be a keyword list, got: #{inspect(options)}"
    end
  end

  @spec to_struct(tuple(), atom()) :: map()
  def to_struct(tuple, module) when is_tuple(tuple),
    do:
      struct(
        module,
        build_struct(module.__attributes__(:query_fields), Tuple.delete_at(tuple, 0))
      )

  @spec to_tuple(map()) :: tuple()
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

  defp invalid_option!(key, _value) when key in @owned_options,
    do: raise(ArgumentError, "the Mnesia table option #{inspect(key)} is set by ActiveMemory")

  defp invalid_option!(key, value) when key in @supported_options do
    raise ArgumentError,
          "invalid value #{inspect(value)} for the Mnesia table option #{inspect(key)}"
  end

  defp invalid_option!(key, _value) do
    raise ArgumentError,
          "unknown Mnesia table option #{inspect(key)}, expected one of #{inspect(@supported_options)}"
  end

  defp user_property?(property), do: is_tuple(property) and tuple_size(property) >= 1

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

  defp validate_option(:local_content, value) when is_boolean(value),
    do: {:local_content, value}

  defp validate_option(:majority, value) when is_boolean(value), do: {:majority, value}

  defp validate_option(:ram_copies, node_list) when is_list(node_list),
    do: {:ram_copies, node_list}

  defp validate_option(:storage_properties, properties) when is_list(properties) do
    case Keyword.keyword?(properties) do
      true -> {:storage_properties, properties}
      false -> invalid_option!(:storage_properties, properties)
    end
  end

  defp validate_option(:type, type) when type in @types, do: {:type, type}

  defp validate_option(:user_properties, properties) when is_list(properties) do
    case Enum.all?(properties, &user_property?/1) do
      true -> {:user_properties, properties}
      false -> invalid_option!(:user_properties, properties)
    end
  end

  defp validate_option(key, value), do: invalid_option!(key, value)
end
