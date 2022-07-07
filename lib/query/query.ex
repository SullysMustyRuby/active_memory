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
  end

  defp reduce({operand, _meta, [lhs, rhs]}) do
    quote do
      {unquote(operand), unquote(reduce(lhs)), unquote(reduce(rhs))}
    end
  end

  defp reduce({atom, meta, _} = ast) when is_atom(atom) and is_list(meta) do
    quote do
      unquote(ast)
    end
  end

  defp reduce(value) when is_atom(value), do: value

  defp reduce(value) when is_binary(value), do: value

  defp reduce(value) when is_integer(value), do: value
end
