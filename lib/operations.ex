defmodule ActiveMemory.Operations do
  @moduledoc """
  The shared implementation of the table operations and store setup used by
  `ActiveMemory.Store` and `ActiveMemory.ActiveRepo`.

  Every function takes the table module explicitly and dispatches to that table's
  configured adapter, applying the common validation, `uuid` handling, seeding and
  `before_init` logic. This keeps the single-table `Store` and the multi-table
  `Repo` sharing one implementation rather than duplicating it.
  """

  @spec all(atom()) :: list(map())
  def all(table), do: adapter(table).all(table)

  @doc """
  Run the `before_init` methods for a store.

  `spec` is `:default`, a single `{method, args}` tuple, or a list of such tuples.
  `module` is the module the methods are defined on (the `Store` or `Repo`).
  """
  @spec before_init(:default | tuple() | list(), module()) :: {:ok, atom()}
  def before_init(:default, _module), do: {:ok, :default}

  def before_init({method, args}, module) when is_list(args) do
    :erlang.apply(module, method, args)
    {:ok, :before_init_success}
  end

  def before_init(methods, module) when is_list(methods) do
    Enum.each(methods, &before_init(&1, module))
    {:ok, :before_init_success}
  end

  @spec create_table(atom()) :: {:ok, :created | :recovered} | {:error, any()}
  def create_table(table), do: adapter(table).create_table(table)

  @doc """
  Delete the record provided.

  Returns `:ok` for a struct matching `table` or for `nil`, and
  `{:error, :bad_schema}` when the struct does not match `table`.
  """
  @spec delete(any(), atom()) :: :ok | {:error, any()}
  def delete(%{__struct__: table} = struct, table), do: adapter(table).delete(struct, table)

  def delete(nil, _table), do: :ok

  def delete(_struct, _table), do: {:error, :bad_schema}

  @spec delete_all(atom()) :: :ok | {:error, any()}
  def delete_all(table), do: adapter(table).delete_all(table)

  @doc """
  Get one record matching an attributes map or a `match` query.
  """
  @spec one(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def one(query, table) do
    case adapter(table).one(query, table) do
      {:ok, %{} = record} -> {:ok, record}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  Evaluate `seed_file` and write its records to `table`.

  A `nil` `seed_file` is a no-op. Returns `{:ok, :seed_success}` or
  `{:error, reason}`.
  """
  @spec seed(binary() | nil, atom()) :: {:ok, :seed_success} | {:error, any()}
  def seed(nil, _table), do: {:ok, :seed_success}

  def seed(seed_file, table) do
    with {seeds, _bindings} when is_list(seeds) <- Code.eval_file(seed_file),
         true <- write_seeds(seeds, table) do
      {:ok, :seed_success}
    else
      {:error, message} -> {:error, message}
      _ -> {:error, :seed_failure}
    end
  end

  @doc """
  Get all records matching an attributes map or a `match` query.

  Returns `{:error, :bad_select_query}` for any other query shape.
  """
  @spec select(map() | tuple(), atom()) :: {:ok, list(map())} | {:error, any()}
  def select(query, table) when is_map(query), do: adapter(table).select(query, table)

  def select({_operand, _lhs, _rhs} = query, table), do: adapter(table).select(query, table)

  def select(_query, _table), do: {:error, :bad_select_query}

  @spec withdraw(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def withdraw(query, table), do: adapter(table).withdraw(query, table)

  @doc """
  Write a record to `table`.

  When the schema has a `uuid` field a value is generated if one is absent.
  Returns `{:error, :bad_schema}` when the struct does not match `table`.
  """
  @spec write(map(), atom()) :: {:ok, map()} | {:error, any()}
  def write(%{__struct__: table} = struct, table) do
    case Map.has_key?(struct, :uuid) do
      true -> write_with_uuid(struct, table)
      false -> normal_write(struct, table)
    end
  end

  def write(_struct, _table), do: {:error, :bad_schema}

  defp adapter(table), do: table.__attributes__(:adapter)

  defp normal_write(struct, table), do: adapter(table).write(struct, table)

  defp write_seeds(seeds, table) do
    seeds
    |> Task.async_stream(fn seed -> write(seed, table) end)
    |> Enum.all?(fn {:ok, {result, _seed}} -> result == :ok end)
  end

  defp write_with_uuid(struct, table) do
    case Map.get(struct, :uuid) do
      nil ->
        with_uuid = Map.put(struct, :uuid, Ecto.UUID.generate())
        adapter(table).write(with_uuid, table)

      uuid when is_binary(uuid) ->
        adapter(table).write(struct, table)
    end
  end
end
