defmodule ActiveMemory.Store do
  alias ActiveMemory.Definition

  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      # alias unquote(ActiveMemory.Match)

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

      def all, do: :erlang.apply(@adapter, :all_records, [@table_name])

      def create_table do
        :erlang.apply(@adapter, :create_table, [@table_name])
      end

      def delete(%@table_name{} = struct) do
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

      def withdraw(query_map) when is_map(query_map) do
        :erlang.apply(@adapter, :withdraw, [query_map, @table_name])
      end

      def withdraw({_operand, _lhs, _rhs} = query) do
        :erlang.apply(@adapter, :withdraw, [query, @table_name])
      end

      def withdraw(_), do: {:error, :bad_withdraw_query}

      def write(%@table_name{} = struct) do
        :erlang.apply(@adapter, :write, [struct, @table_name])
      end

      def write(_), do: {:error, :bad_schema}
    end
  end
end

# def create_table(table) do
#   options = Application.get_env(:core_cluster, :mnesia_options)
#   create_table(table, options)
# end

# def create_table(table, options) do
#   with :ok <- Memento.Table.create(table, options) do
#     Logger.info("successfully created table: #{table}")
#   else
#     {:error, {:already_exists, _}} -> copy_table(table)
#     {:error, message} -> Logger.error("Memento.Table.create failed with: #{message}")
#   end

#   :mnesia.wait_for_tables([table], 3000)
# end

# defp add_mnesia_manager do
#   {:ok, _} = :mnesia.change_config(:extra_db_nodes, [@mnesia_manager])
#   :ok
# end

# defp copy_table(table) do
#   case Memento.Table.create_copy(table, node(), :ram_copies) do
#     :ok ->
#       Logger.info("successfully copied table: #{table}")

#     {:error, {:already_exists, _, _}} ->
#       Logger.info("table already exists and recovered: #{table}")

#     {:error, message} ->
#       Logger.error("failed to copy table: #{table} with: #{message}")
#   end
# end
