defmodule MnesiaCompanion.Query do
  defmacro where(query) do
    reduce(query)
    |> Macro.escape()
  end

  defp reduce({operand, _meta, [lhs, rhs]}), do: {operand, reduce(lhs), reduce(rhs)}

  defp reduce(value) when is_atom(value), do: value

  defp reduce(value) when is_binary(value), do: value
end
