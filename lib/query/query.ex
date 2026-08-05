defmodule ActiveMemory.Query do
  @moduledoc """
  The `match/1` macro, for queries that need more than equality.

  An attributes map (`Store.select(%{department: "sales"})`) matches fields for
  equality. When you need comparisons or boolean logic, `match/1` compiles an
  Elixir expression into an ETS/Mnesia match specification at compile time.

  ```elixir
  import ActiveMemory.Query

  query = match(:department == "sales" or :department == "marketing" and :start_date > last_month)
  Store.select(query)
  ```
  """

  @doc """
  Build a match query from an expression.

  Field names are written as atoms — `:age`, not `person.age` — and compared against
  values. The result is passed to `one/1`, `select/2` or `withdraw/1`.

  ## Operators

  Comparison: `==`, `!=`, `===`, `!==`, `<`, `<=`, `>`, `>=`.
  Boolean: `and`, `or`, `not`.

  ```elixir
  match(:age > 30)
  match(:cylon? == true)
  match(:hair_color == "brown" and :age > 45)
  match(:department == "sales" or :department == "marketing")
  ```

  ## Values must be literals of a supported type, or variables

  A value written inline must be an **integer, binary or atom** (booleans and `nil`
  included). Any other literal — a float, a `Decimal`, a `DateTime` — raises a
  `FunctionClauseError` while the query is being compiled:

  ```elixir
  match(:radius_km > 1000.0)      # ** (FunctionClauseError) no function clause
                                  #    matching in ActiveMemory.Query.reduce/1
  ```

  Bind it to a variable instead. A variable is evaluated at runtime, so any term
  works:

  ```elixir
  cutoff = 1000.0
  match(:radius_km > cutoff)      # {:>, :radius_km, 1000.0}

  yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
  match(:inserted_at > yesterday)
  ```

  ## Comparisons use Erlang term order

  The generated match spec compares with Erlang's term ordering, which is correct for
  numbers, binaries and atoms but **not** for struct based values. A `Decimal`,
  `DateTime` or `NaiveDateTime` is a map, and maps sort above every number and compare
  field by field, so `match(:gravity > threshold)` on a `:decimal` field will not do
  what you expect. Filter those in Elixir after reading, or store a comparable
  representation (an integer of milliseconds, for instance) alongside.

  Ordering results has the same caveat handled for you — see the `:order_by` option
  documented on `ActiveMemory.Store`, which does use a value's own `compare/2`.

  ## What it does not support

  There are no joins, aggregates, subqueries, `select` projections or `group_by`. A
  match query filters records of one table and returns whole structs. For anything
  else, read and work in Elixir.
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
