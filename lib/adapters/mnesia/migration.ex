defmodule ActiveMemory.Adapters.Mnesia.Migration do
  @moduledoc """
  Migrations will get run on app startup and are designed to modify :mnesia's schema.

  ## Table Copies
  In the `options` of an ActiveMemory.Table, the copy type and nodes which should have them can be specified.

  ### Ram copies
  Tables that only reside in ram on the nodes specified. The default is `node()`
  Example table using default setting:
  ```elixir
  defmodule Test.Support.Dogs.Dog do
    use ActiveMemory.Table,
      options: [compressed: true, read_concurrency: true]
    .
    # module code
    .
  end
  ```
  The default will be `[node()]` and this table will reside on the `node()` ram.
  Example table spcifing nodes and ram copies:
  ```elixir
  defmodule Test.Support.Dogs.Dog do
    use ActiveMemory.Table,
      options: [compressed: true, read_concurrency: true, ram_copes: [node() | Node.list()]
    .
    # module code
    .
  end
  ```
  All the active nodes in Node.list() and node() will have ram copes of the table.

  ### Disc copies
  Disc copy tables reside **both** in ram and disc on the nodes specified.
  In order to persist to disc the schema must be setup on at lest one running node.
  The default is [] (no nodes).
  Example table spcifing nodes and disc copies:
  ```elixir
  defmodule Test.Support.Dogs.Dog do
    use ActiveMemory.Table,
      options: [compressed: true, read_concurrency: true, disc_copes: [node()]
    .
    # module code
    .
  end
  ```
  The table will have a ram copy and disc copy on `node()`

  ### Disc only copies
  Disc oly tables reside **only** on disc on the nodes specified.
  In order to persist to disc the schema must be setup on at lest one running node.
  The default is [] (no nodes).
  Example table spcifing nodes and disc copies:
  ```elixir
  defmodule Test.Support.Dogs.Dog do
    use ActiveMemory.Table,
      options: [compressed: true, read_concurrency: true, disc_only_copes: [node()]
    .
    # module code
    .
  end
  ```
  The table will only have a disc copy on `node()`

  ## Table Read and Write Access
  Mnesia tables can be set to `read_only` or `read_write`. The default is `read_write`.
  Read only tables updates cannot be performed.
  if you need to change the access use the following syntax: `[access_mode: :read_only]`

  ## Table Types
  Tables can be either a `:set`, `:ordered_set`, or a `:bag`. The default is `:set`
  if you need to change the type use the following syntax: `[type: :bag]`

  ## Indexes
  If Indexes are desired specify an atom attribute list for which Mnesia is to build and maintain an extra index table.
  The qlc query compiler may be able to optimize queries if there are indexes available.
  To specify Indexes use the following syntax: `[index: [:age, :hair_color, :cylon?]]`

  ## Table Load Order
  The load order priority is by default 0 (zero) but can be set to any integer. The tables with the highest load order priority are loaded first at startup.
  If you need to change the load order use the following syntax: `[load_order: 2]`

  ## Majority
  If true, any (non-dirty) update to the table is aborted, unless a majority of the table replicas are available for the commit. When used on a fragmented table, all fragments are given the same the same majority setting.
  If you need to modify the majority use the following syntax: `[majority: true]`
  """

  require Logger

  @doc """
  Bring an existing Mnesia table's schema in line with its `ActiveMemory.Table`
  options.

  Called from `ActiveMemory.Adapters.Mnesia.create_table/1` when the table already
  exists — the `{:ok, :recovered}` path — so a table that outlived this node's process
  picks up option changes made in the code since it was created. It reconciles, in
  order: the replica nodes for each copy type, `access_mode`, `index`, `load_order`
  and `majority`.

  Returns `:ok`. A change Mnesia refuses at runtime — a replica on a node that is
  not reachable, a copy type change it will not perform — is logged as a warning and
  skipped, so the store still starts and the table keeps its current setting for
  that option. The one exception is a copy configuration that is wrong in the code
  itself (the same node under two copy types), which raises `ArgumentError`: it
  would fail identically on every boot, so it is a bug to fix rather than a
  condition to ride out.
  """
  @spec migrate_table_options(atom()) :: :ok
  def migrate_table_options(table) do
    options = table.__attributes__(:table_options)

    validate_copy_options!(options, table)

    migrate_table_copies_to_add(options, table)
    migrate_table_copies_to_delete(options, table)
    migrate_access_mode(options, table)
    migrate_indexes(options, table)
    migrate_load_order(options, table)
    migrate_majority(options, table)

    :ok
  end

  # Supporting methods in alphabetical order
  defp add_copy_type([], _table, _copy_type), do: :ok

  defp add_copy_type(nodes, table, copy_type) do
    for node <- nodes do
      case :mnesia.add_table_copy(table, node, copy_type) do
        {:aborted, {:already_exists, _, _}} ->
          change_table_copy_type(table, node, copy_type)

        result ->
          log_refused(result, table, "add a #{copy_type} replica on #{inspect(node)}")
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
    Enum.each(indexes, fn index ->
      table
      |> :mnesia.add_table_index(index)
      |> log_refused(table, "add an index on #{inspect(index)}")
    end)
  end

  defp change_table_copy_type(table, node, copy_type) do
    case :mnesia.change_table_copy_type(table, node, copy_type) do
      # the replica already has the requested copy type; nothing to change
      {:aborted, {:already_exists, _table, _node, _type}} ->
        :ok

      result ->
        log_refused(result, table, "change the #{inspect(node)} replica to #{copy_type}")
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

  defp copy_options(options) do
    disc_nodes = Keyword.get(options, :disc_copies, []) |> Enum.sort()

    ram_nodes =
      Keyword.get(options, :ram_copies, ram_copy_default(disc_nodes)) |> Enum.sort()

    disc_only_nodes = Keyword.get(options, :disc_only_copies, []) |> Enum.sort()

    {ram_nodes, disc_nodes, disc_only_nodes}
  end

  defp delete_copy_type([], _table), do: :ok

  defp delete_copy_type(nodes, table) do
    Enum.each(nodes, fn node ->
      table
      |> :mnesia.del_table_copy(node)
      |> log_refused(table, "remove the replica on #{inspect(node)}")
    end)
  end

  defp delete_indexes([], _table), do: nil

  defp delete_indexes(indexes, table) do
    Enum.each(indexes, fn index ->
      table
      |> :mnesia.del_table_index(index)
      |> log_refused(table, "remove the index on #{inspect(index)}")
    end)
  end

  defp get_indexes([], _attributes), do: []

  defp get_indexes(indexes, attributes) do
    indexes
    |> Enum.map(fn index -> Enum.at(attributes, index - 2) end)
  end

  # Logs a Mnesia refusal and moves on. Every reconciliation below runs while a
  # `Store` is starting, and a change Mnesia will not perform must not keep the
  # store from booting — the table works, it just keeps its current setting.
  defp log_refused({:atomic, :ok}, _table, _change), do: :ok

  defp log_refused({:aborted, reason}, table, change) do
    Logger.warning(
      "ActiveMemory could not #{change} for #{inspect(table)}: " <>
        "Mnesia refused with #{inspect(reason)}. The table keeps its current setting."
    )

    :ok
  end

  defp migrate_access_mode(options, table) do
    option = Keyword.get(options, :access_mode, :read_write)

    case :mnesia.table_info(table, :access_mode) do
      ^option ->
        :ok

      _other ->
        table
        |> :mnesia.change_table_access_mode(option)
        |> log_refused(table, "change the access mode to #{inspect(option)}")
    end
  end

  defp migrate_indexes(options, table) do
    new_indexes = Keyword.get(options, :index, [])
    indexes = :mnesia.table_info(table, :index)

    current_indexes = get_indexes(indexes, :mnesia.table_info(table, :attributes))

    add_indexes(new_indexes -- current_indexes, table)
    delete_indexes(current_indexes -- new_indexes, table)
    :ok
  end

  defp migrate_load_order(options, table) do
    load_order = Keyword.get(options, :load_order, 0)

    case :mnesia.table_info(table, :load_order) do
      ^load_order ->
        :ok

      _other ->
        table
        |> :mnesia.change_table_load_order(load_order)
        |> log_refused(table, "change the load order to #{load_order}")
    end
  end

  defp migrate_majority(options, table) do
    majority = Keyword.get(options, :majority, false)

    case :mnesia.table_info(table, :majority) do
      ^majority ->
        :ok

      _other ->
        table
        |> :mnesia.change_table_majority(majority)
        |> log_refused(table, "change majority to #{majority}")
    end
  end

  defp migrate_table_copies_to_add(options, table) do
    {ram_nodes, disc_nodes, disc_only_nodes} = copy_options(options)

    add_copy_types(ram_nodes, table, :ram_copies)
    add_copy_types(disc_nodes, table, :disc_copies)
    add_copy_types(disc_only_nodes, table, :disc_only_copies)

    :ok
  end

  defp ram_copy_default(options_disc_nodes) do
    case Enum.member?(options_disc_nodes, node()) do
      true -> []
      false -> [node()]
    end
  end

  defp migrate_table_copies_to_delete(options, table) do
    remove_copy_types(options, table, :ram_copies, [node()])
    remove_copy_types(options, table, :disc_copies)
    remove_copy_types(options, table, :disc_only_copies)

    :ok
  end

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

  # A node holds exactly one copy of a table, so the same node under two copy
  # types is a configuration bug — deterministic on every boot — and raises,
  # unlike a runtime refusal, which is logged and skipped.
  defp validate_copy_options!(options, table) do
    {ram_nodes, disc_nodes, disc_only_nodes} = copy_options(options)

    overlapping =
      Enum.filter(ram_nodes, &(&1 in disc_nodes or &1 in disc_only_nodes)) ++
        Enum.filter(disc_nodes, &(&1 in disc_only_nodes))

    case overlapping do
      [] ->
        :ok

      nodes ->
        raise ArgumentError,
              "#{inspect(table)} lists #{inspect(Enum.uniq(nodes))} under more than one " <>
                "copy type. A node holds exactly one copy of a table, so each node may " <>
                "appear in only one of :ram_copies, :disc_copies and :disc_only_copies."
    end
  end
end
