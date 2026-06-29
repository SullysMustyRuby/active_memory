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
  def all(table), do: adapter(table).all(table) |> reject_expired(table)

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
  Delete every record in `table` whose `expires_at` is at or before `now`
  (milliseconds). Used by the `Store`/`ActiveRepo` sweep to reclaim memory; reads
  already hide expired records, so this is only about freeing them.
  """
  @spec delete_expired(atom(), integer()) :: :ok
  def delete_expired(table, now) do
    table
    |> adapter(table).all()
    |> Enum.each(fn record ->
      case expired_at?(record, now) do
        true -> adapter(table).delete(record, table)
        false -> :ok
      end
    end)
  end

  @doc """
  Get one record matching an attributes map or a `match` query. An expired record
  is treated as `{:error, :not_found}`.
  """
  @spec one(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def one(query, table) do
    case adapter(table).one(query, table) do
      {:ok, %{} = record} -> reject_if_expired(record, table)
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
  def select(query, table) when is_map(query) do
    filter_select(adapter(table).select(query, table), table)
  end

  def select({_operand, _lhs, _rhs} = query, table) do
    filter_select(adapter(table).select(query, table), table)
  end

  def select(_query, _table), do: {:error, :bad_select_query}

  @doc """
  Get one record matching the query, delete it, and return it. An expired record
  is treated as `{:error, :not_found}`.
  """
  @spec withdraw(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def withdraw(query, table) do
    case adapter(table).withdraw(query, table) do
      {:ok, %{} = record} -> reject_if_expired(record, table)
      other -> other
    end
  end

  @doc """
  Write a record to `table`.

  When the schema has a `uuid` field a value is generated if one is absent. When
  the table has a `ttl` the record's `expires_at` is stamped from the current time.
  Returns `{:error, :bad_schema}` when the struct does not match `table`.
  """
  @spec write(map(), atom()) :: {:ok, map()} | {:error, any()}
  def write(%{__struct__: table} = struct, table) do
    struct = put_expiry(struct, table)

    case Map.has_key?(struct, :uuid) do
      true -> write_with_uuid(struct, table)
      false -> normal_write(struct, table)
    end
  end

  def write(_struct, _table), do: {:error, :bad_schema}

  defp adapter(table), do: table.__attributes__(:adapter)

  defp expired?(record, table) do
    case table.__attributes__(:ttl) do
      nil -> false
      _ttl -> expired_at?(record, now_ms())
    end
  end

  defp expired_at?(record, now) do
    case Map.get(record, :expires_at) do
      expires_at when is_integer(expires_at) -> expires_at <= now
      _not_set -> false
    end
  end

  defp filter_select({:ok, records}, table), do: {:ok, reject_expired(records, table)}

  defp filter_select({:error, _message} = error, _table), do: error

  defp normal_write(struct, table), do: adapter(table).write(struct, table)

  defp now_ms, do: System.system_time(:millisecond)

  defp put_expiry(struct, table) do
    case table.__attributes__(:ttl) do
      nil -> struct
      ttl -> Map.put(struct, :expires_at, now_ms() + ttl)
    end
  end

  defp reject_expired(records, table) do
    case table.__attributes__(:ttl) do
      nil -> records
      _ttl -> Enum.reject(records, &expired?(&1, table))
    end
  end

  defp reject_if_expired(record, table) do
    case expired?(record, table) do
      true -> {:error, :not_found}
      false -> {:ok, record}
    end
  end

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
