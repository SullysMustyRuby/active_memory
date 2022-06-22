defmodule MnesiaCompanion.Store do
  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      import unquote(MnesiaCompanion.MatchQuery), only: [{:build, 2}]

      opts = unquote(opts)

      @table Keyword.get(opts, :table)

      def start_link(_opts \\ []) do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        Memento.Table.create!(@table)
        {:ok, %{table: @table}}
      end

      def all do
        Memento.transaction!(fn ->
          Memento.Query.all(@table)
        end)
      end

      def get(query_map) when is_map(query_map) do
        case build(@table, query_map) do
          {:error, message} ->
            {:error, message}

          query ->
            Memento.transaction(fn ->
              Memento.Query.match(@table, query)
            end)
        end
      end

      def insert(%@table{} = struct) do
        Memento.transaction(fn ->
          Memento.Query.write(struct)
        end)
      end

      def insert(_), do: {:error, :bad_schema}

      # def get!(object, query) do
      #   Memento.transaction!(fn ->
      #     Memento.Query.select(object, query)
      #   end)
      # end

      # def get_one(object, id) do
      #   Memento.transaction!(fn ->
      #     Memento.Query.read(object, id)
      #   end)
      # end

      # def select_raw(object, query) do
      #   Memento.transaction!(fn ->
      #     Memento.Query.select_raw(object, query)
      #   end)
      # end

      # def insert!(object) do
      #   Memento.transaction!(fn ->
      #     Memento.Query.write(object)
      #   end)
      # end

      # def delete(object) do
      #   Memento.transaction!(fn ->
      #     Memento.Query.delete_record(object)
      #   end)
      # end

      # def clear(table) do
      #   :mnesia.clear_table(table)
      # end

      # def withdraw(object, query) when is_tuple(query) do
      #   Memento.transaction!(fn ->
      #     case Memento.Query.select(object, query) do
      #       [record | _tail] -> delete_return(record)
      #       [] -> {:error, "#{object} not found"}
      #     end
      #   end)
      # end

      # def withdraw(object, query) when is_list(query) do
      #   Memento.transaction!(fn ->
      #     case Memento.Query.select(object, query) do
      #       [record | _tail] -> delete_return(record)
      #       [] -> {:error, "#{object} not found"}
      #     end
      #   end)
      # end

      # def withdraw(object, id) do
      #   Memento.transaction!(fn ->
      #     case Memento.Query.read(object, id) do
      #       nil -> {:error, "#{object} not found"}
      #       record -> delete_return(record)
      #     end
      #   end)
      # end

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

      # defp delete_return(record) do
      #   Memento.Query.delete_record(record)
      #   {:ok, record}
      # end
    end
  end
end
