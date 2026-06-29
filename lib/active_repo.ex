defmodule ActiveMemory.ActiveRepo do
  @moduledoc """
  # The ActiveRepo

  An `ActiveRepo` manages multiple `ActiveMemory.Table`s from a single process. It
  is the multi-table counterpart to `ActiveMemory.Store` (which manages a single
  table), giving you one supervised entry point and a unified API over many tables.

  > It is named `ActiveRepo` rather than `Repo` so it does not collide with an
  > application's `Ecto.Repo` while keeping the familiar "repo" terminology.

  ```elixir
  defmodule MyApp.ActiveRepo do
    use ActiveMemory.ActiveRepo,
      tables: [
        MyApp.People.Person,
        {MyApp.Dogs.Dog, seed_file: Path.expand("dog_seeds.exs", __DIR__), before_init: [{:warm, []}]}
      ]
  end
  ```

  Add the `ActiveRepo` to your supervision tree like any other process:
  ```elixir
  children = [MyApp.ActiveRepo]
  ```

  Tables may freely mix `:ets` and `:mnesia` adapters; each operation dispatches to
  the adapter configured on the given table.

  ## ActiveRepo API
  Reads and `withdraw` take the table module as the first argument; writes and
  deletes infer the table from the struct.
    - `ActiveRepo.all/1` Get all records stored in a table
    - `ActiveRepo.delete/1` Delete the record provided
    - `ActiveRepo.delete_all/1` Delete all records stored in a table
    - `ActiveRepo.one/2` Get one record from a table matching an attributes search or `match` query
    - `ActiveRepo.select/2` Get all records from a table matching an attributes search or `match` query
    - `ActiveRepo.withdraw/2` Get, delete and return one record from a table
    - `ActiveRepo.write/1` Write a record into its table

  An operation for a struct or table that is not part of the `ActiveRepo` returns
  `{:error, :unknown_table}`.

  ## Concurrency
  Like a `Store`, an `ActiveRepo` is a `GenServer`, but the data functions above are
  **not** routed through that process and are **not** serialized by it. They run in
  the **caller's** process and delegate straight to each table's adapter, so reads
  and writes execute with ETS/Mnesia concurrency — the single `GenServer` is not a
  bottleneck. Only lifecycle and metadata operations (`init`, `state/0`,
  `reload_seeds/1`) use the `GenServer`.

  These functions live on the `GenServer` module purely for **organization**: the
  `ActiveRepo` is the single place responsible for how the application talks to its
  tables, following the Single Responsibility Principle. See the
  [S.T.O.N.E principles](https://www.hpt-consulting.org/blog/stone-principles) for
  the broader design philosophy.

  ## Tables and per-table options
  Each entry of `tables:` is either a table module or a `{table, opts}` tuple. The
  supported per-table options mirror the single-table `ActiveMemory.Store`:
    - `seed_file` a path to a seed file auto loaded when the table is first created
    - `before_init` methods (defined on the `ActiveRepo`) run during the table's setup

  ## Initial State
  Like a `Store`, an `ActiveRepo` is a `GenServer` with state. The default state is:
  ```elixir
  %{started_at: "date time when first started", tables: [MyApp.People.Person, ...]}
  ```
  Supply a `{method, args}` tuple to the `initial_state` keyword to override it; the
  method must return `{:ok, new_state}`.

  ## Resilience
  ETS tables created by an `ActiveRepo` get the same `ActiveMemory.TableHeir`
  protection as a `Store`: they survive an `ActiveRepo` crash and are reclaimed on
  restart, and seed files are not re-run on recovery. See `ActiveMemory.Store` for
  the `before_init` recovery caveat, which applies here as well.
  """

  defmacro __using__(opts) do
    quote do
      use GenServer

      alias ActiveMemory.Operations

      opts = unquote(Macro.expand(opts, __CALLER__))

      @repo_tables Enum.map(Keyword.fetch!(opts, :tables), fn
                     {table, table_opts} -> {table, table_opts}
                     table -> {table, []}
                   end)
      @tables Enum.map(@repo_tables, fn {table, _opts} -> table end)
      @initial_state Keyword.get(opts, :initial_state, :default)

      def start_link(options \\ []) do
        GenServer.start_link(__MODULE__, options, name: __MODULE__)
      end

      @impl true
      def init(_) do
        with :ok <- __setup_tables__(),
             {:ok, initial_state} <- __initial_state__() do
          {:ok, initial_state}
        end
      end

      @spec all(atom()) :: list(map()) | {:error, :unknown_table}
      def all(table) when table in @tables, do: Operations.all(table)

      def all(_table), do: {:error, :unknown_table}

      @spec delete(map()) :: :ok | {:error, any()}
      def delete(%{__struct__: table} = struct) when table in @tables do
        Operations.delete(struct, table)
      end

      def delete(_struct), do: {:error, :unknown_table}

      @spec delete_all(atom()) :: :ok | {:error, any()}
      def delete_all(table) when table in @tables, do: Operations.delete_all(table)

      def delete_all(_table), do: {:error, :unknown_table}

      @spec one(atom(), map() | tuple()) :: {:ok, map()} | {:error, any()}
      def one(table, query) when table in @tables, do: Operations.one(query, table)

      def one(_table, _query), do: {:error, :unknown_table}

      def reload_seeds(table) when table in @tables do
        GenServer.call(__MODULE__, {:reload_seeds, table})
      end

      def reload_seeds(_table), do: {:error, :unknown_table}

      @spec select(atom(), map() | tuple()) :: {:ok, list(map())} | {:error, any()}
      def select(table, query) when table in @tables, do: Operations.select(query, table)

      def select(_table, _query), do: {:error, :unknown_table}

      def state do
        GenServer.call(__MODULE__, :state)
      end

      @spec withdraw(atom(), map() | tuple()) :: {:ok, map()} | {:error, any()}
      def withdraw(table, query) when table in @tables, do: Operations.withdraw(query, table)

      def withdraw(_table, _query), do: {:error, :unknown_table}

      @spec write(map()) :: {:ok, map()} | {:error, any()}
      def write(%{__struct__: table} = struct) when table in @tables do
        Operations.write(struct, table)
      end

      def write(_struct), do: {:error, :unknown_table}

      @impl true
      def handle_call({:reload_seeds, table}, _from, state) do
        {:reply, Operations.seed(__seed_file__(table), table), state}
      end

      @impl true
      def handle_call(:state, _from, state), do: {:reply, state, state}

      # Sent by `ActiveMemory.TableHeir` when it hands a recovered ETS table back to
      # this repo on restart. Ownership transfers with the message; nothing further
      # is required here.
      @impl true
      def handle_info({:"ETS-TRANSFER", _table_ref, _from, _data}, state) do
        {:noreply, state}
      end

      def handle_info(_message, state), do: {:noreply, state}

      # Only the clause matching the compile-time option is generated so the
      # Elixir 1.19+ type checker never sees an unreachable clause.
      if @initial_state == :default do
        defp __initial_state__ do
          {:ok,
           %{
             started_at: DateTime.utc_now(),
             tables: @tables
           }}
        end
      else
        defp __initial_state__ do
          {method, args} = @initial_state
          :erlang.apply(__MODULE__, method, args)
        end
      end

      defp __maybe_seed__(:recovered, _seed_file, _table), do: {:ok, :seed_success}

      defp __maybe_seed__(:created, seed_file, table), do: Operations.seed(seed_file, table)

      defp __seed_file__(table) do
        {_table, table_opts} = List.keyfind(@repo_tables, table, 0)
        Keyword.get(table_opts, :seed_file)
      end

      defp __setup_table__(table, table_opts) do
        with {:ok, table_status} <- Operations.create_table(table),
             {:ok, :seed_success} <-
               __maybe_seed__(table_status, Keyword.get(table_opts, :seed_file), table),
             {:ok, _result} <-
               Operations.before_init(Keyword.get(table_opts, :before_init, :default), __MODULE__) do
          :ok
        end
      end

      defp __setup_tables__ do
        Enum.reduce_while(@repo_tables, :ok, fn {table, table_opts}, _acc ->
          case __setup_table__(table, table_opts) do
            :ok -> {:cont, :ok}
            {:error, _reason} = error -> {:halt, error}
          end
        end)
      end
    end
  end
end
