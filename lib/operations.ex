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
  def create_table(table) do
    validate_expiry_field!(table)
    validate_autogenerate!(table)
    adapter(table).create_table(table)
  end

  @doc """
  Delete the record provided.

  The record is matched in full by the adapter (`:ets.delete_object/2`,
  `:mnesia.delete_object/3`), so a struct that has diverged from the stored copy
  removes nothing and still returns `:ok` — deleting is idempotent and never
  reports whether a record was present. `withdraw/2` is the query based,
  atomic alternative that returns `{:error, :not_found}` when nothing matched.

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
  Schedule the calling process's next expiry sweep when any of `tables` uses a
  `ttl`, and do nothing when none of them do.

  The `ttl` lookup happens here, at runtime, rather than while a `Store` or
  `ActiveRepo` compiles. Reading it at compile time would make every table a
  compile time dependency of its store, which breaks tooling that compiles the
  store's file without the table module loaded.
  """
  @spec schedule_sweep(atom() | list(atom()), integer()) :: :ok
  def schedule_sweep(table, interval) when is_atom(table),
    do: schedule_sweep([table], interval)

  def schedule_sweep(tables, interval) when is_list(tables) do
    case Enum.any?(tables, &ttl?/1) do
      true ->
        Process.send_after(self(), :sweep, interval)
        :ok

      false ->
        :ok
    end
  end

  @doc """
  Delete every expired record from each of `tables` that uses a `ttl`.

  Tables without a `ttl` are skipped, so a repo holding a mix of both only pays
  for the ones that expire.
  """
  @spec sweep_expired(list(atom()), integer()) :: :ok
  def sweep_expired(tables, now) do
    tables
    |> Enum.filter(&ttl?/1)
    |> Enum.each(&delete_expired(&1, now))
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

  Takes a struct or an `Ecto.Changeset`. A valid changeset is applied and its
  struct written; an invalid one returns `{:error, changeset}` with the changeset's
  `action` set to `:insert`, mirroring `Ecto.Repo.insert/1` so a Phoenix form
  renders the errors.

  Any field the table declares as autogenerated and which is still `nil` is
  populated: a `uuid` attribute, or an Ecto schema's autogenerated primary key and
  `timestamps()`. When the table has a `ttl` the record's `expires_at` is stamped
  from the current time. Returns `{:error, :bad_schema}` when the struct does not
  match `table`.
  """
  @spec write(map() | Ecto.Changeset.t(), atom()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t() | any()}
  def write(%Ecto.Changeset{} = changeset, table) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, struct} -> write(struct, table)
      {:error, changeset} -> {:error, changeset}
    end
  end

  def write(%{__struct__: table} = struct, table) do
    struct =
      struct
      |> put_expiry(table)
      |> put_autogenerated(table)

    adapter(table).write(struct, table)
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

  defp now_ms, do: System.system_time(:millisecond)

  # Applies the table's autogenerate specs, which carry Ecto's own
  # `{fields, {module, function, args}}` shape. A field holding a value is left
  # alone so a caller supplied key or timestamp is never overwritten.
  defp put_autogenerated(struct, table) do
    Enum.reduce(table.__attributes__(:autogenerate), struct, fn {fields, {mod, fun, args}}, acc ->
      Enum.reduce(fields, acc, fn field, acc ->
        case Map.get(acc, field) do
          nil -> Map.put(acc, field, apply(mod, fun, args))
          _set -> acc
        end
      end)
    end)
  end

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

  defp ttl?(table), do: not is_nil(table.__attributes__(:ttl))

  defp reject_if_expired(record, table) do
    case expired?(record, table) do
      true -> {:error, :not_found}
      false -> {:ok, record}
    end
  end

  # Builds the autogenerate specs once at startup so a key ActiveMemory cannot
  # generate (an autogenerated integer `:id`) fails when the table is created
  # rather than silently writing every record under a `nil` key.
  defp validate_autogenerate!(table) do
    _specs = table.__attributes__(:autogenerate)
    :ok
  end

  # A `ttl` table without an `expires_at` attribute would silently never expire,
  # so a misconfigured schema (possible with Ecto schema tables, where the field
  # must be declared by hand) is rejected loudly at table creation.
  defp validate_expiry_field!(table) do
    case table.__attributes__(:ttl) do
      nil ->
        :ok

      _ttl ->
        case Enum.member?(table.__attributes__(:query_fields), :expires_at) do
          true ->
            :ok

          false ->
            raise ArgumentError,
                  "#{inspect(table)} is configured with a :ttl but has no :expires_at field. " <>
                    "Ecto schema tables must declare it: `field :expires_at, :integer`."
        end
    end
  end

  defp write_seeds(seeds, table) do
    seeds
    |> Task.async_stream(fn seed -> write(seed, table) end)
    |> Enum.all?(fn {:ok, {result, _seed}} -> result == :ok end)
  end
end
