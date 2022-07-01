defmodule ActiveMemory.Store do
  @moduledoc """
  The Store 
  """
  alias ActiveMemory.Definition

  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      use GenServer

      opts = unquote(opts)

      @table_name Keyword.get(opts, :table)
      @table_type Keyword.get(opts, :type, :mnesia)
      @adapter Definition.set_adapter(@table_type)
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
      def all, do: :erlang.apply(@adapter, :all, [@table_name])

      def create_table do
        :erlang.apply(@adapter, :create_table, [@table_name, []])
      end

      @spec all() :: :ok | {:error, any()}
      def delete(%{__struct__: @table_name} = struct) do
        :erlang.apply(@adapter, :delete, [struct, @table_name])
      end

      def delete(nil), do: :ok

      def delete(_), do: {:error, :bad_schema}

      @spec delete_all() :: :ok | {:error, any()}
      def delete_all do
        :erlang.apply(@adapter, :delete_all, [@table_name])
      end

      @spec one(map() | list(any())) :: {:ok, map()} | {:error, any()}
      def one(query) do
        :erlang.apply(@adapter, :one, [query, @table_name])
      end

      def reload_seeds do
        GenServer.call(__MODULE__, :reload_seeds)
      end

      @spec select(map() | list(any())) :: {:ok, list(map())} | {:error, any()}
      def select(query) when is_map(query) do
        :erlang.apply(@adapter, :select, [query, @table_name])
      end

      def select({_operand, _lhs, _rhs} = query) do
        :erlang.apply(@adapter, :select, [query, @table_name])
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
      def write(%@table_name{} = struct) do
        :erlang.apply(@adapter, :write, [struct, @table_name])
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
           table_name: @table_name
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
