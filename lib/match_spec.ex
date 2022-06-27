defmodule ActiveMemory.MatchSpec do
  @result [:"$_"]

  def build(query, table) do
    query_map = :erlang.apply(table, :__info__, []) |> Map.get(:query_map)
    match_head = :erlang.apply(table, :__info__, []) |> Map.get(:match_head)
    guards = reduce(query, query_map)

    [{match_head, [guards], @result}]
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
