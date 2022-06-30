defmodule ActiveMemory.Store do
  alias ActiveMemory.Definition

  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      opts = unquote(opts)

      @table_name Keyword.get(opts, :table)
      @table_type Keyword.get(opts, :type, :mnesia)
      @adapter Definition.set_adapter(@table_type)

      def start_link(_opts \\ []) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        create_table()
        {:ok, %{table_name: @table_name}}
      end

      def all, do: :erlang.apply(@adapter, :all, [@table_name])

      def create_table do
        :erlang.apply(@adapter, :create_table, [@table_name, []])
      end

      def delete(%{__struct__: @table_name} = struct) do
        :erlang.apply(@adapter, :delete, [struct, @table_name])
      end

      def delete(nil), do: :ok

      def delete(_), do: {:error, :bad_schema}

      def delete_all do
        :erlang.apply(@adapter, :delete_all, [@table_name])
      end

      def one(query) do
        :erlang.apply(@adapter, :one, [query, @table_name])
      end

      def select(query) when is_map(query) do
        :erlang.apply(@adapter, :select, [query, @table_name])
      end

      def select({_operand, _lhs, _rhs} = query) do
        :erlang.apply(@adapter, :select, [query, @table_name])
      end

      def select(_), do: {:error, :bad_select_query}

      def withdraw(query) do
        with {:ok, %{} = record} <- one(query),
             :ok <- delete(record) do
          {:ok, record}
        else
          {:ok, nil} -> {:ok, nil}
          {:error, message} -> {:error, message}
        end
      end

      def write(%@table_name{} = struct) do
        :erlang.apply(@adapter, :write, [struct, @table_name])
      end

      def write(_), do: {:error, :bad_schema}
    end
  end
end
