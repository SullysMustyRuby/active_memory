defmodule ActiveMemory.Adapters.Mnesia.Migration do
  def migrate_table_options(table) do
    table.__attributes__(:table_options)
    |> migrate_access_mode(table)
    |> migrate_ram_copies(table)
    |> migrate_disc_copies(table)
    |> migrate_disc_only_copies(table)
    |> migrate_indexes(table)
    |> migrate_load_order(table)
    |> migrate_majority(table)

    :ok
  end

  defp migrate_access_mode(options, table) do
    option = Keyword.get(options, :access_mode, :read_write)
    :mnesia.change_table_access_mode(table, option)
    options
  end

  defp migrate_disc_copies(options, table) do
    disc_copies = Keyword.get(options, :disc_copies, [])
    :mnesia.change_table_copy_type(table, disc_copies, :disc_copies)
    options
  end

  defp migrate_disc_only_copies(options, table) do
    disc_only_copies = Keyword.get(options, :disc_only_copies, [])
    :mnesia.change_table_copy_type(table, disc_only_copies, :disc_only_copies)
    options
  end

  defp migrate_ram_copies(options, table) do
    ram_copy_node = Keyword.get(options, :ram_copies, node())
    :mnesia.change_table_copy_type(table, ram_copy_node, :ram_copies)
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
    :mnesia.change_table_load_order(table, load_order)
    options
  end

  defp migrate_majority(options, table) do
    majority = Keyword.get(options, :majority, false)
    :mnesia.change_table_majority(table, majority)
    options
  end

  defp get_indexes([], _attributes), do: []

  defp get_indexes(indexes, attributes) do
    indexes
    |> Enum.map(fn index -> Enum.at(attributes, index - 2) end)
  end

  defp add_indexes([], _table), do: nil

  defp add_indexes(indexes, table) do
    Enum.each(indexes, fn index -> :mnesia.add_table_index(table, index) end)
  end

  defp delete_indexes([], _table), do: nil

  defp delete_indexes(indexes, table) do
    Enum.each(indexes, fn index -> :mnesia.del_table_index(table, index) end)
  end
end
