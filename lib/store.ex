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

      opts = unquote(Macro.expand(opts, __CALLER__))

      ##### FIX do we need to parse these here? Can we just parse as needed?
      @table Keyword.get(opts, :table)
      @before_init Keyword.get(opts, :before_init, :default)
      @initial_state Keyword.get(opts, :initial_state, :default)
      @seed_file Keyword.get(opts, :seed_file, nil)

      def start_link(options \\ []) do
        GenServer.start_link(__MODULE__, options, name: __MODULE__)
      end

      ##### FIX else fallthrough #####
      @impl true
      def init(_) do
        with :ok <- create_table(),
             {:ok, :seed_success} <- __run_seeds_file__(),
             {:ok, _result} <- before_init(@before_init),
             {:ok, initial_state} <- __initial_state__() do
          {:ok, initial_state}
        end
      end

      @spec all() :: list(map())
      def all, do: :erlang.apply(@table.__attributes__(:adapter), :all, [@table])

      def create_table do
        :erlang.apply(@table.__attributes__(:adapter), :create_table, [@table])
      end

      @spec delete(any()) :: :ok | {:error, any()}
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
        case :erlang.apply(@table.__attributes__(:adapter), :one, [query, @table]) do
          {:ok, %{} = record} -> {:ok, record}
          {:error, message} -> {:error, message}
        end
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
          {:error, message} -> {:error, message}
        end
      end

      @spec write(map()) :: {:ok, map()} | {:error, any()}
      def write(%@table{} = struct) do
        case Map.has_key?(struct, :uuid) do
          true -> write_with_uuid(struct)
          false -> normal_write(struct)
        end
      end

      def write(_), do: {:error, :bad_schema}

      defp write_with_uuid(%@table{} = struct) do
        case Map.get(struct, :uuid) do
          nil ->
            with_uuid = Map.put(struct, :uuid, Ecto.UUID.generate())
            :erlang.apply(@table.__attributes__(:adapter), :write, [with_uuid, @table])

          uuid when is_binary(uuid) ->
            :erlang.apply(@table.__attributes__(:adapter), :write, [struct, @table])
        end
      end

      def normal_write(%@table{} = struct) do
        :erlang.apply(@table.__attributes__(:adapter), :write, [struct, @table])
      end

      @impl true
      def handle_call(:reload_seeds, _from, state) do
        {:reply, __run_seeds_file__(), state}
      end

      @impl true
      def handle_call(:state, _from, state), do: {:reply, state, state}

      defp before_init(:default), do: {:ok, :default}

      defp before_init({method, args}) when is_list(args) do
        :erlang.apply(__MODULE__, method, args)
        {:ok, :before_init_success}
      end

      defp before_init(methods) when is_list(methods) do
        Enum.each(methods, &before_init(&1))
        {:ok, :before_init_success}
      end

      defp write_seeds(seeds) do
        seeds
        |> Task.async_stream(&write(&1))
        |> Enum.all?(fn {:ok, {result, _seed}} -> result == :ok end)
      end

      ##### FIX this is ugly AI gen
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

      if @seed_file == nil do
        defp __run_seeds_file__, do: {:ok, :seed_success}
      else
        defp __run_seeds_file__ do
          with {seeds, _} when is_list(seeds) <- Code.eval_file(@seed_file),
               true <- write_seeds(seeds) do
            {:ok, :seed_success}
          else
            {:error, message} -> {:error, message}
            _ -> {:error, :seed_failure}
          end
        end

      end
    end
  end
end
