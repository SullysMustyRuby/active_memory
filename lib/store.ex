defmodule ActiveMemory.Store do
  @moduledoc """
  # The Store

  ## Store API
    - `Store.all/0` Get all records stored
    - `Store.delete/1` Delete the record provided
    - `Store.delete_all/0` Delete all records stored
    - `Store.one/1` Get one record matching either an attributes search or `match` query
    - `Store.select/1` Get all records matching either an attributes search or `match` query
    - `Store.withdraw/1` Get one record matching either an attributes search or `match` query, delete the record and return it
    - `Store.write/1` Write a record into the memmory table

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

      def start_link(options \\ []) do
        GenServer.start_link(__MODULE__, options, name: __MODULE__)
      end

      @impl true
      def init(_) do
        with {:ok, table_status} <- create_table(),
             {:ok, :seed_success} <- __maybe_run_seeds__(table_status),
             {:ok, _result} <- Operations.before_init(@before_init, __MODULE__),
             {:ok, initial_state} <- __initial_state__() do
          {:ok, initial_state}
        end
      end

      @spec all() :: list(map())
      def all, do: Operations.all(@table)

      def create_table, do: Operations.create_table(@table)

      @spec delete(any()) :: :ok | {:error, any()}
      def delete(struct), do: Operations.delete(struct, @table)

      @spec delete_all() :: :ok | {:error, any()}
      def delete_all, do: Operations.delete_all(@table)

      @spec one(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def one(query), do: Operations.one(query, @table)

      def reload_seeds do
        GenServer.call(__MODULE__, :reload_seeds)
      end

      @spec select(map() | list(any())) :: {:ok, list(map())} | {:error, any()}
      def select(query), do: Operations.select(query, @table)

      def state do
        GenServer.call(__MODULE__, :state)
      end

      @spec withdraw(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def withdraw(query), do: Operations.withdraw(query, @table)

      @spec write(map()) :: {:ok, map()} | {:error, any()}
      def write(struct), do: Operations.write(struct, @table)

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

      def handle_info(_message, state), do: {:noreply, state}

      # A recovered table already holds its data, so seeding is skipped to avoid
      # duplicating or clobbering the surviving records.
      defp __maybe_run_seeds__(:recovered), do: {:ok, :seed_success}

      defp __maybe_run_seeds__(:created), do: Operations.seed(@seed_file, @table)

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
