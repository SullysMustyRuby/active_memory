defmodule ActiveMemory.Store do
  @moduledoc """
  # The Store

  ## Store API
    - `Store.all/1` Get all records stored, optionally ordered and paged (see [Ordering and paging](#module-ordering-and-paging))
    - `Store.count/1` Count the records stored, without reading them (see [Counting](#module-counting))
    - `Store.delete/1` Delete the record provided, matched in full (see [Deleting a record](#module-deleting-a-record))
    - `Store.delete_all/0` Delete all records stored
    - `Store.exists?/2` Whether any record matches an attributes search or `match` query
    - `Store.get/1` Get the record with the given primary key, or `{:error, :not_found}`
    - `Store.get!/1` Like `get/1` but raises `ActiveMemory.NotFoundError`
    - `Store.get_by/1` Get the single record matching an attributes search
    - `Store.get_by!/1` Like `get_by/1` but raises `ActiveMemory.NotFoundError`
    - `Store.one/1` Get one record matching either an attributes search or `match` query. Raises `ActiveMemory.MultipleResultsError` when several match
    - `Store.one!/1` Like `one/1` but raises `ActiveMemory.NotFoundError`
    - `Store.reload/1` Re-read a record from the table by its primary key
    - `Store.reload!/1` Like `reload/1` but raises `ActiveMemory.NotFoundError`
    - `Store.select/2` Get all records matching either an attributes search or `match` query, optionally ordered and paged
    - `Store.withdraw/1` **Atomically** get one record matching either an attributes search or `match` query, delete the record and return it — exactly one concurrent caller wins, making it safe for take-once workloads
    - `Store.write/1` Write a record into the memory table, from a struct or an `Ecto.Changeset`. An invalid changeset is returned as `{:error, changeset}` with its `action` set to `:insert`, exactly like `Ecto.Repo.insert/1`

  ## Reading a single record
  `get/1` reads by primary key — the table's first field, which is what ETS and
  Mnesia key a record on. That is `:uuid` on a table using
  `auto_generate_uuid: true`, an Ecto schema's declared primary key, or simply the
  first field declared.

  ```elixir
  {:ok, person} = MyApp.People.Store.get(uuid)
  person = MyApp.People.Store.get!(uuid)          # raises ActiveMemory.NotFoundError
  {:ok, person} = MyApp.People.Store.get_by(%{email: "kara@galactica.com"})
  ```

  A query that is meant to find one record but matches several raises
  `ActiveMemory.MultipleResultsError` from `one/1`, `one!/1`, `get_by/1` and
  `get_by!/1`, as `Ecto.Repo.one/2` does. Use `select/2` when many records are
  expected.

  Because reads and writes match a record in full, a struct held across a change
  goes stale; `reload/1` gets the current copy.

  ## Counting
  `count/1` asks the table for its size (`:ets.info/2`, `:mnesia.table_info/2`), so
  it is O(1) and never copies records out — unlike `length(all())`.

  On a table with a `ttl` that number includes records that have expired but have
  not been swept yet, so it can exceed what the reads return. Pass `sweep: true` to
  delete those first and get a count that agrees with the reads:

  ```elixir
  MyApp.Tokens.Store.count()               # O(1), may include expired records
  MyApp.Tokens.Store.count(sweep: true)    # sweeps first, then counts
  ```

  `exists?/2` has to match a query against fields, so it costs a scan rather than
  being O(1). It accepts `sweep: true` as well, though the answer never depends on
  it, since reads already ignore an expired record.

  ## Ordering and paging
  `all/1` and `select/2` take `:order_by`, `:limit` and `:offset`:

  ```elixir
  MyApp.People.Store.all(order_by: :last, limit: 20)
  MyApp.People.Store.all(order_by: [{:desc, :age}, :last], offset: 20, limit: 20)
  MyApp.People.Store.select(%{cylon?: true}, order_by: :last)
  ```

  Neither ETS nor Mnesia can order a result, so this sorts after reading —
  `O(n log n)` over the matched records, not an index backed sort. Without an
  `:order_by` the order is whatever the table returns, which for a `:set` table is
  unspecified.

  Values are compared with their own `compare/2` when they have one, so `Decimal`,
  `DateTime`, `NaiveDateTime`, `Date` and `Time` fields sort correctly instead of by
  Erlang term order, which compares those structs field by field.

  ## Deleting a record
  `delete/1` removes an **exact** record match: the struct you pass is compared
  field for field against what is stored (`:ets.delete_object/2`,
  `:mnesia.delete_object/3`). Pass a struct that has diverged from the stored copy
  — a stale read, or one you modified in memory — and nothing is removed, yet the
  call still returns `:ok`, the same answer `delete/1` gives for a record that was
  never there.

  This is deliberate. It is the only correct behavior for a `:bag` table, where
  several records share a key, and on a `:set` table it means a delete never
  clobbers a newer version of a record written since you read it.

  When you hold an identifier rather than a record you know is current, reach for
  `withdraw/1` instead. It matches on a query, so staleness cannot affect it, it is
  atomic, and it tells you whether anything was actually removed:

  ```elixir
  case MyApp.People.Store.withdraw(%{uuid: uuid}) do
    {:ok, person} -> # removed, and here is the record that was stored
    {:error, :not_found} -> # nothing matched
  end
  ```

  ## Concurrency
  A `Store` is a `GenServer`, but the data functions above (`all/0`, `one/1`,
  `select/1`, `write/1`, `delete/1`, `withdraw/1`, `delete_all/0`) are **not**
  routed through that process and are **not** serialized by it. They are ordinary
  module functions that run in the **caller's** process, delegating straight to the
  table's adapter (and therefore to `:ets`/`:mnesia`). Concurrency is governed by
  ETS/Mnesia themselves, so many processes read and write in parallel — the single
  `GenServer` is not a bottleneck. Only lifecycle and metadata operations (`init`,
  `state/0`, `reload_seeds/0`) actually use the `GenServer`.

  These functions live on the `GenServer` module purely for **organization**: the
  `Store` is the single place responsible for how the application talks to its
  table, following the Single Responsibility Principle. See the
  [S.T.O.N.E principles](https://www.hpt-consulting.org/blog/stone-principles) for
  the broader design philosophy.

  ## Expiry (TTL)
  When the `Store`'s `Table` declares a `ttl` (see `ActiveMemory.Table`), records
  expire automatically. Expiry is enforced in two ways: reads (`one/1`, `select/1`,
  `all/0`, `withdraw/1`) never return an expired record, and the `Store` periodically
  sweeps expired records to reclaim memory. The sweep cadence defaults to one minute
  and can be set with the `sweep_interval` option (milliseconds):
  ```elixir
  defmodule MyApp.Tokens.Store do
  use ActiveMemory.Store,
    table: MyApp.Tokens.Token,
    sweep_interval: :timer.seconds(30)
  end
  ```
  The sweep only runs when the table has a `ttl`; otherwise it is never scheduled.

  ## Seeding
  When starting a `Store` there is an option to provide a valid seed file and have the `Store` auto load seeds contained in the file.
  ```elixir
  defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    seed_file: Path.expand("person_seeds.exs", __DIR__)
  end
  ```

  ## Before `init`
  All stores are `GenServers` and have `init` functions. While those are abstracted you can still specify methods to run during the `init` phase of the GenServer startup. Use the `before_init` keyword and add the methods as tuples with the arguments.
  ```elixir
  defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    before_init: [{:run_me, ["arg1", "arg2", ...]}, {:run_me_too, []}]
  end
  ```

  > #### `before_init` and table recovery {: .warning}
  >
  > For ETS stores, the table is preserved across a store crash/restart by
  > `ActiveMemory.TableHeir`. On such a recovery seed files are *not* re-run, but
  > `before_init` methods **always** run, including on recovery. If a
  > `before_init` method writes records with unique or generated keys (for
  > example a `uuid`), running it again on recovery can create duplicates.
  >
  > How to handle this is left to the implementer. One option is to make any
  > `before_init` write follow a "find or create" pattern — check with `one/1`
  > before calling `write/1` — so the method is idempotent across restarts:
  >
  > ```elixir
  > def run_me(args) do
  >   record = build_record(args)
  >
  >   case one(%{key: record.key}) do
  >     {:ok, existing} -> {:ok, existing}
  >     {:error, :not_found} -> write(record)
  >   end
  > end
  > ```

  ## Initial State
  All stores are `GenServers` and thus have a state. The default state is a map as such:
  ```elixir
  %{started_at: "date time when first started", table_name: MyApp.People.Person}
  ```
  This default state can be overwritten with a new state structure or values by supplying a method and arguments as a tuple to the keyword `initial_state`. The method must return `{:ok, new_state}`.

  ```elixir
  defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    initial_state: {:initial_state_method, ["arg1", "arg2", ...]}
  end
  ```
  """

  @default_sweep_interval :timer.seconds(60)

  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)

      use GenServer

      alias ActiveMemory.Operations

      opts = unquote(Macro.expand(opts, __CALLER__))

      @table Keyword.get(opts, :table)
      @before_init Keyword.get(opts, :before_init, :default)
      @initial_state Keyword.get(opts, :initial_state, :default)
      @seed_file Keyword.get(opts, :seed_file, nil)
      @sweep_interval Keyword.get(opts, :sweep_interval, unquote(@default_sweep_interval))

      def start_link(options \\ []) do
        GenServer.start_link(__MODULE__, options, name: __MODULE__)
      end

      @impl true
      def init(_) do
        with {:ok, table_status} <- create_table(),
             {:ok, :seed_success} <- __maybe_run_seeds__(table_status),
             {:ok, _result} <- Operations.before_init(@before_init, __MODULE__),
             {:ok, initial_state} <- __initial_state__() do
          __schedule_sweep__()
          {:ok, initial_state}
        end
      end

      @spec all(keyword()) :: list(map())
      def all(opts \\ []), do: Operations.all(@table, opts)

      @spec count(keyword()) :: non_neg_integer()
      def count(opts \\ []), do: Operations.count(@table, opts)

      def create_table, do: Operations.create_table(@table)

      @spec delete(any()) :: :ok | {:error, any()}
      def delete(struct), do: Operations.delete(struct, @table)

      @spec delete_all() :: :ok | {:error, any()}
      def delete_all, do: Operations.delete_all(@table)

      @spec exists?(map() | tuple(), keyword()) :: boolean()
      def exists?(query, opts \\ []), do: Operations.exists?(query, @table, opts)

      @spec get(any()) :: {:ok, map()} | {:error, any()}
      def get(key), do: Operations.get(key, @table)

      @spec get!(any()) :: map()
      def get!(key), do: Operations.get!(key, @table)

      @spec get_by(map()) :: {:ok, map()} | {:error, any()}
      def get_by(query), do: Operations.get_by(query, @table)

      @spec get_by!(map()) :: map()
      def get_by!(query), do: Operations.get_by!(query, @table)

      @spec one(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def one(query), do: Operations.one(query, @table)

      @spec one!(map() | list(any())) :: map()
      def one!(query), do: Operations.one!(query, @table)

      @spec reload(map()) :: {:ok, map()} | {:error, any()}
      def reload(struct), do: Operations.reload(struct, @table)

      @spec reload!(map()) :: map()
      def reload!(struct), do: Operations.reload!(struct, @table)

      def reload_seeds do
        GenServer.call(__MODULE__, :reload_seeds)
      end

      @spec select(map() | list(any()), keyword()) :: {:ok, list(map())} | {:error, any()}
      def select(query, opts \\ []), do: Operations.select(query, @table, opts)

      def state do
        GenServer.call(__MODULE__, :state)
      end

      @spec withdraw(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def withdraw(query), do: Operations.withdraw(query, @table)

      @spec write(map() | Ecto.Changeset.t()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t() | any()}
      def write(struct_or_changeset), do: Operations.write(struct_or_changeset, @table)

      @impl true
      def handle_call(:reload_seeds, _from, state) do
        {:reply, Operations.seed(@seed_file, @table), state}
      end

      @impl true
      def handle_call(:state, _from, state), do: {:reply, state, state}

      # Sent by `ActiveMemory.TableHeir` when it hands a recovered ETS table back
      # to this store on restart. Ownership transfers with the message; nothing
      # further is required here.
      @impl true
      def handle_info({:"ETS-TRANSFER", _table_ref, _from, _data}, state) do
        {:noreply, state}
      end

      # Periodically reclaims memory from expired records when the table has a `ttl`.
      def handle_info(:sweep, state) do
        Operations.delete_expired(@table, System.system_time(:millisecond))
        __schedule_sweep__()
        {:noreply, state}
      end

      def handle_info(_message, state), do: {:noreply, state}

      # A recovered table already holds its data, so seeding is skipped to avoid
      # duplicating or clobbering the surviving records.
      defp __maybe_run_seeds__(:recovered), do: {:ok, :seed_success}

      defp __maybe_run_seeds__(:created), do: Operations.seed(@seed_file, @table)

      # Schedules the next expiry sweep only when the table actually uses a `ttl`.
      # The `ttl` is read at runtime by `Operations`, never here: inspecting the
      # table module while this one compiles would make the table a compile time
      # dependency, which breaks tooling that loads this file on its own.
      defp __schedule_sweep__, do: Operations.schedule_sweep(@table, @sweep_interval)

      # Only the clause matching the compile-time option is generated so the
      # Elixir 1.19+ type checker never sees an unreachable clause.
      if @initial_state == :default do
        defp __initial_state__ do
          {:ok,
           %{
             started_at: DateTime.utc_now(),
             table_name: @table
           }}
        end
      else
        defp __initial_state__ do
          {method, args} = @initial_state
          :erlang.apply(__MODULE__, method, args)
        end
      end
    end
  end
end
