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

  ## Initial State
  All stores are `GenServers` and thus have a state. The default state is an array as such:
  ```elixir
  %{started_at: "date time when first started", table: MyApp.People.Store}
  ```
  This default state can be overwritten with a new state structure or values by supplying a method and arguments as a tuple to the keyword `initial_state`.

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

      opts = unquote(Macro.expand(opts, __CALLER__))

      @table Keyword.get(opts, :table)
      @before_init Keyword.get(opts, :before_init, :default)
      @seed_file Keyword.get(opts, :seed_file, nil)
      @initial_state Keyword.get(opts, :initial_state, :default)

      def start_link(_opts \\ []) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      @impl true
      def init(_) do
        with :ok <- create_table(),
             {:ok, :seed_success} <- run_seeds_file(@seed_file),
             :ok <- before_init(@before_init),
             {:ok, initial_state} <- initial_state(@initial_state) do
          {:ok, initial_state}
        end
      end

      @spec all() :: list(map())
      def all, do: :erlang.apply(@table.__attributes__(:adapter), :all, [@table])

      def create_table do
        :erlang.apply(@table.__attributes__(:adapter), :create_table, [@table, []])
      end

      @spec all() :: :ok | {:error, any()}
      def delete(%{__struct__: @table} = struct) do
        :erlang.apply(@table.__attributes__(:adapter), :delete, [struct, @table])
      end

      def delete(nil), do: :ok

      def delete(_), do: {:error, :bad_schema}

      @spec delete_all() :: :ok | {:error, any()}
      def delete_all do
        :erlang.apply(@table.__attributes__(:adapter), :delete_all, [@table])
      end

      @spec one(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def one(query) do
        :erlang.apply(@table.__attributes__(:adapter), :one, [query, @table])
      end

      def reload_seeds do
        GenServer.call(__MODULE__, :reload_seeds)
      end

      @spec select(map() | list(any())) :: {:ok, list(map())} | {:error, any()}
      def select(query) when is_map(query) do
        :erlang.apply(@table.__attributes__(:adapter), :select, [query, @table])
      end

      def select({_operand, _lhs, _rhs} = query) do
        :erlang.apply(@table.__attributes__(:adapter), :select, [query, @table])
      end

      def select(_), do: {:error, :bad_select_query}

      def state do
        GenServer.call(__MODULE__, :state)
      end

      @spec withdraw(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def withdraw(query) do
        with {:ok, %{} = record} <- one(query),
             :ok <- delete(record) do
          {:ok, record}
        else
          {:ok, nil} -> {:ok, nil}
          {:error, message} -> {:error, message}
        end
      end

      @spec write(map()) :: {:ok, map()} | {:error, any()}
      def write(%@table{uuid: uuid} = struct) when is_binary(uuid) do
        :erlang.apply(@table.__attributes__(:adapter), :write, [struct, @table])
      end

      def write(%@table{uuid: nil} = struct) do
        with_uuid = Map.put(struct, :uuid, UUID.uuid4())
        :erlang.apply(@table.__attributes__(:adapter), :write, [with_uuid, @table])
      end

      def write(%@table{} = struct) do
        :erlang.apply(@table.__attributes__(:adapter), :write, [struct, @table])
      end

      def write(_), do: {:error, :bad_schema}

      @impl true
      def handle_call(:reload_seeds, _from, state) do
        {:reply, run_seeds_file(@seed_file), state}
      end

      @impl true
      def handle_call(:state, _from, state), do: {:reply, state, state}

      defp before_init(:default), do: :ok

      defp before_init({method, args}) when is_list(args) do
        :erlang.apply(__MODULE__, method, args)
      end

      defp before_init(methods) when is_list(methods) do
        methods
        |> Enum.into([], &before_init(&1))
        |> Enum.all?(&(&1 == :ok))
        |> case do
          true -> :ok
          _ -> {:error, :before_init_failure}
        end
      end

      defp initial_state(:default) do
        {:ok,
         %{
           started_at: DateTime.utc_now(),
           table_name: @table
         }}
      end

      defp initial_state({method, args}) do
        :erlang.apply(__MODULE__, method, args)
      end

      defp run_seeds_file(nil), do: {:ok, :seed_success}

      defp run_seeds_file(file) when is_binary(file) do
        with {seeds, _} when is_list(seeds) <- Code.eval_file(@seed_file),
             true <- write_seeds(seeds) do
          {:ok, :seed_success}
        else
          {:error, message} -> {:error, message}
          _ -> {:error, :seed_failure}
        end
      end

      defp write_seeds(seeds) do
        seeds
        |> Task.async_stream(&write(&1))
        |> Enum.all?(fn {:ok, {result, _seed}} -> result == :ok end)
      end
    end
  end
end
