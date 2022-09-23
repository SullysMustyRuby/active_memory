defmodule ActiveMemory.Adapters.Mnesia.Migration do
  def migrate_table_options(table) do
    table.__attributes__(:table_options)
    |> migrate_table_copies_to_add(table)
    |> migrate_table_copies_to_delete(table)
    |> migrate_access_mode(table)
    |> migrate_indexes(table)
    |> migrate_load_order(table)
    |> migrate_majority(table)

    :ok
  end

  # Supporting methods in alphabetical order
  defp add_copy_type([], _table, _copy_type), do: :ok

  defp add_copy_type(nodes, table, copy_type) do
    for node <- nodes do
      case :mnesia.add_table_copy(table, node, copy_type) do
        {:aborted, {:already_exists, _, _}} ->
          change_table_copy_type(table, node, copy_type)

        {:atomic, :ok} ->
          :ok
      end
    end

    :ok
  end

  defp add_copy_types(options_nodes, table, copy_type) do
    table
    |> :mnesia.table_info(copy_type)
    |> Enum.sort()
    |> compare_nodes_to_add(options_nodes)
    |> add_copy_type(table, copy_type)
  end

  defp add_indexes([], _table), do: nil

  defp add_indexes(indexes, table) do
    Enum.each(indexes, fn index -> :mnesia.add_table_index(table, index) end)
  end

  defp change_table_copy_type(table, node, copy_type) do
    case :mnesia.change_table_copy_type(table, node, copy_type) do
      {:atomic, :ok} -> :ok
      other -> other
    end
  end

  defp compare_nodes_to_add([], options_nodes), do: options_nodes

  defp compare_nodes_to_add(_current_nodes, []), do: []

  defp compare_nodes_to_add(current_nodes, options_nodes) do
    options_nodes -- current_nodes
  end

  defp compare_nodes_to_remove([], _options_nodes), do: []

  defp compare_nodes_to_remove(current_nodes, []), do: current_nodes

  defp compare_nodes_to_remove(current_nodes, options_nodes) do
    current_nodes -- options_nodes
  end

  defp copy_type_validation(_ram_nodes, [], []), do: :ok

  defp copy_type_validation([], _disc_nodes, []), do: :ok

  defp copy_type_validation([], [], _disc_only_nodes), do: :ok

  defp copy_type_validation([], disc_nodes, disc_only_nodes) do
    disc_nodes_validation(disc_nodes, disc_only_nodes)
  end

  defp copy_type_validation(ram_nodes, [], disc_only_nodes) do
    ram_nodes
    |> Enum.any?(&Enum.member?(disc_only_nodes, &1))
    |> parse_check(:ram_copies)
  end

  defp copy_type_validation(ram_nodes, disc_nodes, []) do
    ram_nodes
    |> Enum.any?(&Enum.member?(disc_nodes, &1))
    |> parse_check(:ram_copies)
  end

  defp copy_type_validation(ram_nodes, disc_nodes, disc_only_nodes) do
    with {:ok, :ram_copies} <- ram_nodes_validation(ram_nodes, disc_nodes, disc_only_nodes),
         {:ok, :disc_copies} <- disc_nodes_validation(disc_nodes, disc_only_nodes) do
      :ok
    end
  end

  defp delete_copy_type([], _table), do: :ok

  defp delete_copy_type(nodes, table) do
    Enum.each(nodes, &:mnesia.del_table_copy(table, &1))
  end

  defp delete_indexes([], _table), do: nil

  defp delete_indexes(indexes, table) do
    Enum.each(indexes, fn index -> :mnesia.del_table_index(table, index) end)
  end

  defp disc_nodes_validation(disc_nodes, disc_only_nodes) do
    disc_nodes
    |> Enum.any?(&Enum.member?(disc_only_nodes, &1))
    |> parse_check(:disc_copies)
  end

  defp get_indexes([], _attributes), do: []

  defp get_indexes(indexes, attributes) do
    indexes
    |> Enum.map(fn index -> Enum.at(attributes, index - 2) end)
  end

  defp migrate_access_mode(options, table) do
    option = Keyword.get(options, :access_mode, :read_write)

    case :mnesia.table_info(table, :access_mode) do
      ^option -> :ok
      _ -> :mnesia.change_table_access_mode(table, option)
    end

    options
  end

  defp migrate_indexes(options, table) do
    new_indexes = Keyword.get(options, :index, [])
    indexes = :mnesia.table_info(table, :index)

    current_indexes = get_indexes(indexes, :mnesia.table_info(table, :attributes))

    add_indexes(new_indexes -- current_indexes, table)
    delete_indexes(current_indexes -- new_indexes, table)
    options
  end

  defp migrate_load_order(options, table) do
    load_order = Keyword.get(options, :load_order, 0)

    case :mnesia.table_info(table, :load_order) do
      ^load_order -> :ok
      _ -> :mnesia.change_table_load_order(table, load_order)
    end

    options
  end

  defp migrate_majority(options, table) do
    majority = Keyword.get(options, :majority, false)

    case :mnesia.table_info(table, :majority) do
      ^majority -> :ok
      _ -> :mnesia.change_table_majority(table, majority)
    end

    options
  end

  defp migrate_table_copies_to_add(options, table) do
    options_ram_nodes = Keyword.get(options, :ram_copies, [node()]) |> Enum.sort()
    options_disc_nodes = Keyword.get(options, :disc_copies, []) |> Enum.sort()
    options_disc_only_nodes = Keyword.get(options, :disc_only_copies, []) |> Enum.sort()

    val = copy_type_validation(options_ram_nodes, options_disc_nodes, options_disc_only_nodes)

    with :ok <-
           copy_type_validation(options_ram_nodes, options_disc_nodes, options_disc_only_nodes),
         :ok <- add_copy_types(options_ram_nodes, table, :ram_copies),
         :ok <- add_copy_types(options_disc_nodes, table, :disc_copies),
         :ok <-
           add_copy_types(
             options_disc_only_nodes,
             table,
             :disc_only_copies
           ) do
      options
    end
  end

  defp migrate_table_copies_to_delete(options, table) do
    with :ok <- remove_copy_types(options, table, :ram_copies, [node()]),
         :ok <- remove_copy_types(options, table, :disc_copies),
         :ok <- remove_copy_types(options, table, :disc_only_copies) do
      options
    end
  end

  defp parse_check(false, _copy_type), do: :ok

  defp parse_check(true, copy_type),
    do: {:error, "#{copy_type} options are invalid. Please read the documentation"}

  defp remove_copy_types(options, table, copy_type, default_nodes \\ []) do
    options_nodes =
      options
      |> Keyword.get(copy_type, default_nodes)
      |> Enum.sort()

    table
    |> :mnesia.table_info(copy_type)
    |> Enum.sort()
    |> compare_nodes_to_remove(options_nodes)
    |> delete_copy_type(table)
  end

  defp ram_nodes_validation(ram_nodes, disc_nodes, disc_only_nodes) do
    ram_nodes
    |> Enum.any?(&(Enum.member?(disc_nodes, &1) or Enum.member?(disc_only_nodes, &1)))
    |> parse_check(:ram_copies)
  end
end
