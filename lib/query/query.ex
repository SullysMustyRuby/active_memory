defmodule ActiveMemory.Query do
  @moduledoc """

  ## The `match` query syntax
  Using the `match` macro you can structure a basic query.  
  ```elixir
  query = match(:department == "sales" or :department == "marketing" and :start_date > last_month)
  Store.select(query)
  ```
  """
  defmacro match(query) do
    reduce(query)
    |> Macro.escape()
  end

  defp reduce({operand, _meta, [lhs, rhs]}), do: {operand, reduce(lhs), reduce(rhs)}

  defp reduce(value) when is_atom(value), do: value

  defp reduce(value) when is_binary(value), do: value

  defp reduce(value) when is_integer(value), do: value
end
