defmodule MnesiaCompanion.Store do
  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      alias unquote(MnesiaCompanion.Match)

      opts = unquote(opts)

      @table_name Keyword.get(opts, :table)
      @table_type Keyword.get(opts, :type, :mnesia)

      def start_link(_opts \\ []) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        create_table(@table_type)
        {:ok, %{table_name: @table_name}}
      end

      def all, do: all_records(@table_type)

      def clear_table do
        :mnesia.clear_table(@table_name)
      end

      def delete(%@table_name{} = struct) do
        Memento.transaction!(fn ->
          Memento.Query.delete_record(struct)
        end)
      end

      def delete(_), do: {:error, :bad_schema}

      def one(query_map) when is_map(query_map) do
        with {:ok, query} <- Match.build(@table_name, query_map),
             {:ok, [record | []]} <- query_match(query) do
          {:ok, record}
        else
          {:ok, []} -> {:ok, nil}
          {:ok, records} when is_list(records) -> {:error, :more_than_one_result}
          {:error, message} -> {:error, message}
        end
      end

      def one({_operand, _lhs, _rhs} = where) do
        case where_select(where) do
          {:ok, [record | []]} -> {:ok, record}
          {:ok, []} -> {:ok, nil}
          {:ok, records} when is_list(records) -> {:error, :more_than_one_result}
          {:error, message} -> {:error, message}
        end
      end

      def select(query_map) when is_map(query_map) do
        case Match.build(@table_name, query_map) do
          {:error, message} ->
            {:error, message}

          {:ok, query} ->
            query_match(query)
        end
      end

      def select({_operand, _lhs, _rhs} = where), do: where_select(where)

      def select(_), do: {:error, :bad_where_query}

      def withdraw(query_map) when is_map(query_map) do
        with {:ok, query} <- Match.build(@table_name, query_map),
             {:ok, [record | []]} <- query_match(query),
             :ok <- delete(record) do
          {:ok, record}
        else
          {:ok, []} -> {:ok, nil}
          {:ok, records} when is_list(records) -> {:error, :more_than_one_result}
          {:error, message} -> {:error, message}
        end
      end

      def withdraw({_operand, _lhs, _rhs} = where) do
        with {:ok, [record | []]} <- where_select(where),
             :ok <- delete(record) do
          {:ok, record}
        else
          {:ok, []} -> {:ok, nil}
          {:ok, records} when is_list(records) -> {:error, :more_than_one_result}
          {:error, message} -> {:error, message}
        end
      end

      def write(%@table_name{} = struct), do: write_record(struct, @table_type)

      def write(_), do: {:error, :bad_schema}

      defp all_records(:ets) do
        :ets.tab2list(@table_name)
        |> Task.async_stream(fn record -> :erlang.apply(@table_name, :to_struct, [record]) end)
        |> Enum.into([])
      end

      defp all_records(:mnesia) do
        Memento.transaction!(fn ->
          Memento.Query.all(@table_name)
        end)
      end

      defp create_table(:ets) do
        :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
      end

      defp create_table(:mnesia) do
        Memento.Table.create!(@table_name)
      end

      defp query_match(query) do
        Memento.transaction(fn ->
          Memento.Query.match(@table_name, query)
        end)
      end

      defp where_select(where) do
        Memento.transaction(fn ->
          Memento.Query.select(@table_name, where)
        end)
      end

      defp write_record(struct, :ets) do
        with ets_tuple when is_tuple(ets_tuple) <-
               :erlang.apply(@table_name, :to_tuple, [struct]),
             true <- :ets.insert(@table_name, ets_tuple) do
          {:ok, struct}
        else
          false -> {:error, :write_fail}
          {:error, message} -> {:error, message}
        end
      end

      defp write_record(struct, :mnesia) do
        Memento.transaction(fn ->
          Memento.Query.write(struct)
        end)
      end
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
