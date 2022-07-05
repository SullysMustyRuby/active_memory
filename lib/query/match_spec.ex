defmodule ActiveMemory.Query.MatchSpec do
  @moduledoc false

  @result [:"$_"]

  def build(query, query_map, match_head) do
    [{match_head, [reduce(query, query_map)], @result}]
  end

  defp reduce({operand, lhs, rhs}, query_map) when is_tuple(lhs) and is_tuple(rhs) do
    {translate(operand), reduce(lhs, query_map), reduce(rhs, query_map)}
  end

  defp reduce({operand, lhs, rhs}, query_map) when is_tuple(lhs) do
    {translate(operand), reduce(lhs, query_map), rhs}
  end

  defp reduce({operand, lhs, rhs}, query_map) when is_tuple(rhs) do
    {translate(operand), lhs, reduce(rhs, query_map)}
  end

  defp reduce({operand, attribute, value}, query_map)
       when is_atom(attribute) and not is_tuple(value) and is_map(query_map) do
    variable = Map.get(query_map, attribute, attribute)
    {translate(operand), variable, value}
  end

  defp reduce({operand, attribute, value}, query_map)
       when is_atom(attribute) and not is_tuple(value) do
    variable = Keyword.get(query_map, attribute, attribute)
    {translate(operand), variable, value}
  end

  defp translate(:<=), do: :"=<"

  defp translate(:!=), do: :"/="

  defp translate(:===), do: :"=:="

  defp translate(:!==), do: :"=/="

  defp(translate(operand), do: operand)
end
