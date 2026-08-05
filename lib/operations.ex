defmodule ActiveMemory.Operations do
  @moduledoc """
  The shared implementation of the table operations and store setup used by
  `ActiveMemory.Store` and `ActiveMemory.ActiveRepo`.

  Every function takes the table module explicitly and dispatches to that table's
  configured adapter, applying the common validation, `uuid` handling, seeding and
  `before_init` logic. This keeps the single-table `Store` and the multi-table
  `Repo` sharing one implementation rather than duplicating it.
  """

  alias ActiveMemory.MultipleResultsError
  alias ActiveMemory.NotFoundError

  @doc """
  Get every record in `table`, optionally ordered and paged.

  See `order/2` for the `:order_by`, `:limit` and `:offset` options.
  """
  @spec all(atom(), keyword()) :: list(map())
  def all(table, opts \\ []) do
    table
    |> adapter(table).all()
    |> reject_expired(table)
    |> arrange(opts)
  end

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

  @doc """
  Count the records in `table` without reading them.

  The count comes from the table itself (`:ets.info/2`, `:mnesia.table_info/2`), so
  it is O(1) and does not copy records out of the table.

  On a table with a `ttl` that number includes records that have expired but have
  not been swept yet, so it can exceed what the reads return. Pass `sweep: true` to
  delete the expired records first and get a count that matches the reads, at the
  cost of a full pass over the table.
  """
  @spec count(atom(), keyword()) :: non_neg_integer()
  def count(table, opts \\ []) do
    maybe_sweep(table, opts)
    adapter(table).count(table)
  end

  @spec create_table(atom()) :: {:ok, :created | :recovered} | {:error, any()}
  def create_table(table) do
    validate_expiry_field!(table)
    validate_autogenerate!(table)
    validate_primary_key!(table)
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
  Whether any record in `table` matches the query.

  Unlike `count/2` this has to look at the records, because a query is matched
  against their fields, so it costs a scan. Accepts `sweep: true` to reclaim
  expired records first; the answer itself is unaffected, since reads already
  ignore an expired record.
  """
  @spec exists?(map() | tuple(), atom(), keyword()) :: boolean()
  def exists?(query, table, opts \\ []) do
    maybe_sweep(table, opts)

    case select(query, table) do
      {:ok, []} -> false
      {:ok, [_record | _rest]} -> true
      {:error, _message} -> false
    end
  end

  @doc """
  Get the record whose primary key is `key`.

  The primary key is the table's first field — `:uuid` on a table using
  `auto_generate_uuid: true`, an Ecto schema's declared key, or the first field
  declared. Returns `{:error, :not_found}` when there is no such record.
  """
  @spec get(any(), atom()) :: {:ok, map()} | {:error, any()}
  def get(key, table), do: one(%{table.__attributes__(:primary_key) => key}, table)

  @doc """
  Like `get/2` but raises `ActiveMemory.NotFoundError` when there is no such record.
  """
  @spec get!(any(), atom()) :: map()
  def get!(key, table) do
    case get(key, table) do
      {:ok, record} ->
        record

      {:error, :not_found} ->
        raise NotFoundError,
          table: table,
          query: %{table.__attributes__(:primary_key) => key}
    end
  end

  @doc """
  Get the single record matching an attributes map.

  Raises `ActiveMemory.MultipleResultsError` when more than one record matches, as
  `Ecto.Repo.get_by/3` does.
  """
  @spec get_by(map(), atom()) :: {:ok, map()} | {:error, any()}
  def get_by(query, table) when is_map(query), do: one(query, table)

  @doc """
  Like `get_by/2` but raises `ActiveMemory.NotFoundError` when nothing matches.
  """
  @spec get_by!(map(), atom()) :: map()
  def get_by!(query, table) when is_map(query) do
    case get_by(query, table) do
      {:ok, record} -> record
      {:error, :not_found} -> raise NotFoundError, table: table, query: query
    end
  end

  @doc """
  Get one record matching an attributes map or a `match` query. An expired record
  is treated as `{:error, :not_found}`.

  Raises `ActiveMemory.MultipleResultsError` when the query matches more than one
  record, mirroring `Ecto.Repo.one/2`. Use `select/3` when many records are
  expected.
  """
  @spec one(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def one(query, table) do
    case adapter(table).one(query, table) do
      {:ok, %{} = record} ->
        reject_if_expired(record, table)

      {:error, :more_than_one_result} ->
        raise MultipleResultsError, table: table, query: query

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Like `one/2` but raises `ActiveMemory.NotFoundError` when nothing matches.
  """
  @spec one!(map() | tuple(), atom()) :: map()
  def one!(query, table) do
    case one(query, table) do
      {:ok, record} -> record
      {:error, :not_found} -> raise NotFoundError, table: table, query: query
    end
  end

  @doc """
  Re-read `struct` from `table` by its primary key.

  Reads and writes match a record in full, so a struct held across a change can go
  stale. `reload/2` gets the current copy. Returns `{:error, :not_found}` when the
  record is gone.
  """
  @spec reload(map(), atom()) :: {:ok, map()} | {:error, any()}
  def reload(%{__struct__: table} = struct, table) do
    get(Map.get(struct, table.__attributes__(:primary_key)), table)
  end

  def reload(_struct, _table), do: {:error, :bad_schema}

  @doc """
  Like `reload/2` but raises `ActiveMemory.NotFoundError` when the record is gone.
  """
  @spec reload!(map(), atom()) :: map()
  def reload!(%{__struct__: table} = struct, table) do
    get!(Map.get(struct, table.__attributes__(:primary_key)), table)
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
  Get all records matching an attributes map or a `match` query, optionally ordered
  and paged. See `order/2` for the options.

  Returns `{:error, :bad_select_query}` for any other query shape.
  """
  @spec select(map() | tuple(), atom(), keyword()) :: {:ok, list(map())} | {:error, any()}
  def select(query, table, opts \\ [])

  def select(query, table, opts) when is_map(query) do
    filter_select(adapter(table).select(query, table), table, opts)
  end

  def select({_operand, _lhs, _rhs} = query, table, opts) do
    filter_select(adapter(table).select(query, table), table, opts)
  end

  def select(_query, _table, _opts), do: {:error, :bad_select_query}

  @doc """
  Sort and page a list of records.

  Neither ETS nor Mnesia can order a result for us, so this sorts in the caller
  after reading — `O(n log n)` over the matched records, not an index backed sort.

  Options:
    - `:order_by` a field, `{:asc | :desc, field}`, or a list of either to break ties
    - `:offset` records to drop after ordering
    - `:limit` records to keep after the offset

  Values are compared with the struct's own `compare/2` when it has one, so
  `Decimal`, `DateTime`, `NaiveDateTime`, `Date` and `Time` fields order correctly
  rather than by Erlang term order.
  """
  @spec order(list(map()), keyword()) :: list(map())
  def order(records, opts), do: arrange(records, opts)

  @doc """
  Get one record matching the query, delete it, and return it. An expired record
  is treated as `{:error, :not_found}`.
  """
  @spec withdraw(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def withdraw(query, table) do
    case adapter(table).withdraw(query, table) do
      {:ok, %{} = record} ->
        reject_if_expired(record, table)

      # Deleting an arbitrary one of several matches would be wrong, and as with
      # `one/2` an unselective query is a caller bug rather than an outcome to
      # branch on.
      {:error, :more_than_one_result} ->
        raise MultipleResultsError, table: table, query: query

      other ->
        other
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

  defp arrange(records, opts) do
    records
    |> order_by(Keyword.get(opts, :order_by))
    |> drop(Keyword.get(opts, :offset))
    |> take(Keyword.get(opts, :limit))
  end

  defp order_by(records, nil), do: records

  defp order_by(records, spec) do
    specs = Enum.map(List.wrap(spec), &normalize_order/1)

    Enum.sort(records, fn left, right -> ordered?(left, right, specs) end)
  end

  defp normalize_order({direction, field}) when direction in [:asc, :desc] and is_atom(field),
    do: {direction, field}

  defp normalize_order(field) when is_atom(field), do: {:asc, field}

  defp normalize_order(other) do
    raise ArgumentError,
          "invalid :order_by #{inspect(other)}. Use a field, {:asc | :desc, field}, " <>
            "or a list of either."
  end

  # Ties fall through to the next spec; running out of specs leaves the pair in
  # whatever order the sort had them.
  defp ordered?(_left, _right, []), do: true

  defp ordered?(left, right, [{direction, field} | rest]) do
    case compare_values(Map.get(left, field), Map.get(right, field)) do
      :eq -> ordered?(left, right, rest)
      :lt -> direction == :asc
      :gt -> direction == :desc
    end
  end

  # Erlang term order puts every map above every number and compares struct fields
  # alphabetically, which would sort Decimal and the calendar types wrongly. Those
  # all expose `compare/2`, so use it whenever both values are the same struct.
  defp compare_values(%module{} = left, %module{} = right) do
    case function_exported?(module, :compare, 2) do
      true -> module.compare(left, right)
      false -> term_compare(left, right)
    end
  end

  defp compare_values(left, right), do: term_compare(left, right)

  defp term_compare(left, right) when left < right, do: :lt
  defp term_compare(left, right) when left > right, do: :gt
  defp term_compare(_left, _right), do: :eq

  defp drop(records, nil), do: records

  defp drop(records, offset) when is_integer(offset) and offset >= 0,
    do: Enum.drop(records, offset)

  defp take(records, nil), do: records
  defp take(records, limit) when is_integer(limit) and limit >= 0, do: Enum.take(records, limit)

  defp filter_select({:ok, records}, table, opts),
    do: {:ok, records |> reject_expired(table) |> arrange(opts)}

  defp filter_select({:error, _message} = error, _table, _opts), do: error

  defp maybe_sweep(table, opts) do
    case Keyword.get(opts, :sweep, false) do
      true -> sweep_expired([table], now_ms())
      false -> :ok
    end
  end

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

  # Resolving the primary key raises when an Ecto schema declares one that is not
  # the table key, so touch it at startup rather than on the first `get/2`.
  defp validate_primary_key!(table) do
    _key = table.__attributes__(:primary_key)
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
