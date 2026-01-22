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

  ## Before `init`
  All stores are `GenServers` and have `init` functions. While those are abstracted you can still specify methods to run during the `init` phase of the GenServer startup. Use the `before_init` keyword and add the methods as tuples with the arguments.
  ```elixir
  defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    before_init: [{:run_me, ["arg1", "arg2", ...]}, {:run_me_too, []}]
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

      def start_link(options \\ []) do
        GenServer.start_link(__MODULE__, options, name: __MODULE__)
      end

      @impl true
      def init(_) do
        with :ok <- create_table(),
             {:ok, _result} <- before_init(@before_init) do
          {:ok, initial_state()}
        end
      end

      @spec all() :: list(map())
      def all, do: :erlang.apply(@table.__attributes__(:adapter), :all, [@table])

      def create_table do
        :erlang.apply(@table.__attributes__(:adapter), :create_table, [@table])
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
            with_uuid = Map.put(struct, :uuid, UUID.uuid4())
            :erlang.apply(@table.__attributes__(:adapter), :write, [with_uuid, @table])

          uuid when is_binary(uuid) ->
            :erlang.apply(@table.__attributes__(:adapter), :write, [struct, @table])
        end
      end

      def normal_write(%@table{} = struct) do
        :erlang.apply(@table.__attributes__(:adapter), :write, [struct, @table])
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

      defp initial_state do
        {:ok,
         %{
           started_at: DateTime.utc_now(),
           table_name: @table
         }}
      end
    end
  end
end
