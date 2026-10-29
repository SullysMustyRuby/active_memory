defmodule ActiveMemory.Query.MatchGuards do
  @moduledoc false

  # A match pattern treats some terms as syntax rather than values: `:_` matches
  # anything, atoms like `:"$1"` are variables, and a map matches any map holding
  # its keys. A value that is safe as a literal stays in the pattern so key and
  # index lookups still apply. Any other value is bound to its field's variable
  # and compared exactly in a guard, wrapped in `:const` so it is never evaluated.

  @spec build(module(), map()) :: {:ok, {tuple(), list()}} | {:error, :query_schema_mismatch}
  def build(table, query_map) do
    table.__attributes__(:query_fields)
    |> validate_query(query_map)
    |> build_match(query_map, table.__attributes__(:query_map))
  end

  # Build a `{pattern, guards}` pair that matches exactly `record` and nothing else.
  @spec exact(tuple()) :: {tuple(), list()}
  def exact(record) when is_tuple(record) do
    record
    |> Tuple.to_list()
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {value, index}, acc -> bind(value, :"$#{index}", acc) end)
    |> to_pattern()
  end

  defp bind(value, variable, {pattern, guards}) do
    case literal?(value) do
      true -> {[value | pattern], guards}
      false -> {[variable | pattern], [{:"=:=", variable, {:const, value}} | guards]}
    end
  end

  defp build_match({:ok, attributes}, query_map, variables) do
    query =
      attributes
      |> Enum.reduce({[], []}, fn key, {pattern, guards} = acc ->
        case Map.fetch(query_map, key) do
          {:ok, value} -> bind(value, Keyword.fetch!(variables, key), acc)
          :error -> {[:_ | pattern], guards}
        end
      end)
      |> to_pattern()

    {:ok, query}
  end

  defp build_match(error, _query_map, _variables), do: error

  defp literal?(:_), do: false

  defp literal?(value) when is_atom(value),
    do: not String.starts_with?(Atom.to_string(value), "$")

  defp literal?(value) when is_map(value), do: false

  defp literal?(value) when is_tuple(value), do: value |> Tuple.to_list() |> literal?()

  defp literal?([head | tail]), do: literal?(head) and literal?(tail)

  defp literal?(_value), do: true

  defp to_pattern({pattern, guards}),
    do: {pattern |> Enum.reverse() |> List.to_tuple(), Enum.reverse(guards)}

  defp validate_query(attributes, query_map) do
    case Enum.all?(query_map, fn {key, _value} -> Enum.member?(attributes, key) end) do
      true -> {:ok, attributes}
      false -> {:error, :query_schema_mismatch}
    end
  end
end
