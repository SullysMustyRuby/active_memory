defmodule ActiveMemory.Query.MatchSpec do
  @moduledoc false

  @result [:"$_"]

  @boolean [:and, :or, :andalso, :orelse, :xor]

  def build(query, query_map, match_head) do
    [{match_head, [reduce(query, query_map)], @result}]
  end

  defp reduce({operand, lhs, rhs}, query_map) when operand in @boolean do
    {translate(operand), reduce(lhs, query_map), reduce(rhs, query_map)}
  end

  # A comparison names a field on the left and holds a value on the right. The value
  # is wrapped in `:const` so the match engine never reads an atom like `:"$1"` as a
  # variable or a tuple as a guard expression.
  defp reduce({operand, attribute, value}, query_map) when is_atom(attribute) do
    {translate(operand), variable(attribute, query_map), {:const, value}}
  end

  defp reduce({atom, meta, _} = ast, _query_map) when is_atom(atom) and is_list(meta), do: ast

  # A bare value in a boolean position, such as the `true` in `:age > 1 and true`.
  defp reduce(value, _query_map) when not is_tuple(value), do: {:const, value}

  defp translate(:<=), do: :"=<"

  defp translate(:!=), do: :"/="

  defp translate(:===), do: :"=:="

  defp translate(:!==), do: :"=/="

  defp translate(operand), do: operand

  # A name that is not a field is compared as a constant, so an atom like `:"$1"`
  # on the left is never read as a match variable.
  defp variable(attribute, query_map) when is_map(query_map),
    do: Map.get(query_map, attribute, {:const, attribute})

  defp variable(attribute, query_map),
    do: Keyword.get(query_map, attribute, {:const, attribute})
end
