defmodule ActiveMemory.Table do
  @moduledoc """

  Define your table attributes and defaults just like a regular Elixir module struct.
  Keys can have default values defined.

  Example Table:
  ```elixir
  defmodule Test.Support.People.Person do
    use ActiveMemory.Table,
      options: [index: [:last, :cylon?]]

    attributes do
      field :email, :string
      field :first, :string
      field :last, :string
      field :hair_color, :string
      field :age, :integer
      field :cylon?, :boolean
    end
  end
  ```

  ## Options when creating tables
  `ActiveMemory.Table` support almost all of the same options as `:ets` and `:mneisia`. 
  Please be aware that the options are different for `:ets` and `:mneisia`. 
  Further reading can be found with [ETS docs](https://www.erlang.org/doc/man/ets.html) and [Mnesia docs](https://www.erlang.org/doc/man/mnesia.html).
  All options should be structured as a [Keyword list](https://hexdocs.pm/elixir/1.12/Keyword.html). 

  Example:
  ```elixir
  use ActiveMemory.Table,
    type: :ets,
    options: [compressed: true, read_concurrency: true, type: :protected]
  ```

  ### Mnesia Options
  #### Table Read and Write Access
  Mnesia tables can be set to `read_only` or `read_write`. The default is `read_write`.
  Read only tables updates cannot be performed.
  if you need to change the access use the following syntax: `[access_mode: :read_only]`

  #### Table Types
  Tables can be either a `:set`, `:ordered_set`, or a `:bag`. The default is `:set`
  if you need to change the type use the following syntax: `[type: :bag]`

  #### Disk Copies
  A list of nodes can be specified to maintain disk copies of the table. Nodes specified will recieve a replica of the table. Disk copy talbes still maintain a ram copy of the table as well.
  By default all tables are `ram_copies` and no `disc_copies` are specified.
  if you need to specify nodes use following syntax: `[disc_copies: [node1, node2, node3, ...]]`

  #### Disk Only Copies
  A list of nodes can be specified to maintain only disk copies. A disc only table replica is kept on disc only and unlike the other replica types, the contents of the replica do not reside in RAM. These replicas are considerably slower than replicas held in RAM.
  if you need to specify nodes use following syntax: `[disc_only_copies: [node1, node2, node3, ...]]`

  #### Ram Copies
  A list of nodes can be specified to maintain ram copies of the table. Nodes specified will recieve a replica of the table.
  By default all tables are set to ram_copies: `[ram_copies: [node()]]`
  if you need to specify nodes use following syntax: `[ram_copies: [node1, node2, node3, ...]]`

  #### Indexes
  If Indexes are desired specify an atom attribute list for which Mnesia is to build and maintain an extra index table. 
  The qlc query compiler may be able to optimize queries if there are indexes available.
  To specify Indexes use the following syntax: `[index: [:age, :hair_color, :cylon?]]`

  #### Table Load Order
  The load order priority is by default 0 (zero) but can be set to any integer. The tables with the highest load order priority are loaded first at startup.
  If you need to change the load order use the following syntax: `[load_order: 2]`

  #### Majority
  If true, any (non-dirty) update to the table is aborted, unless a majority of the table replicas are available for the commit. When used on a fragmented table, all fragments are given the same the same majority setting.
  If you need to modify the majority use the following syntax: `[majority: true]`

  ### ETS Options
  #### Table Access
  Access options are: `:public` `:protected` or `:private`. The default access is `:public` 
  if you need to change the access use the following syntax: `[access: :private]`

  #### Table Types
  Tables can be either a `:set`, `:ordered_set`, `:bag`, or a `:duplicate_bag`. The default is `:set`
  if you need to change the type use the following syntax: `[type: :bag]`

  #### Compression
  Compression can be used to help shrink the size of the memory the data consumes, however this does mean the access is slower.
  The default is `false` where no compression happens. 
  if you need to change the compression use the following syntax: `[Compression: true]`

  #### Read Concurrency
  From ETS documentation:
  Performance tuning. Defaults to `false`. When set to true, the table is optimized for concurrent read operations. When this option is enabled read operations become much cheaper; especially on systems with multiple physical processors. However, switching between read and write operations becomes more expensive.
  You typically want to enable this option when concurrent read operations are much more frequent than write operations, or when concurrent reads and writes comes in large read and write bursts (that is, many reads not interrupted by writes, and many writes not interrupted by reads).
  You typically do not want to enable this option when the common access pattern is a few read operations interleaved with a few write operations repeatedly. In this case, you would get a performance degradation by enabling this option.
  Option read_concurrency can be combined with option write_concurrency. You typically want to combine these when large concurrent read bursts and large concurrent write bursts are common.
  if you need to change the read_concurrency use the following syntax: `[read_concurrency: true]`

  #### Write Concurrency
  From ETS documentation:
  Performance tuning. Defaults to `false`, in which case an operation that mutates (writes to) the table obtains exclusive access, blocking any concurrent access of the same table until finished. If set to true, the table is optimized for concurrent write access. Different objects of the same table can be mutated (and read) by concurrent processes. This is achieved to some degree at the expense of memory consumption and the performance of sequential access and concurrent reading.
  The auto alternative for the write_concurrency option is similar to the true option but automatically adjusts the synchronization granularity during runtime depending on how the table is used. This is the recommended write_concurrency option when using Erlang/OTP 25 and above as it performs well in most scenarios.
  The write_concurrency option can be combined with the options read_concurrency and decentralized_counters. You typically want to combine write_concurrency with read_concurrency when large concurrent read bursts and large concurrent write bursts are common; for more information, see option read_concurrency. It is almost always a good idea to combine the write_concurrency option with the decentralized_counters option.
  Notice that this option does not change any guarantees about atomicity and isolation. Functions that makes such promises over many objects (like insert/2) gain less (or nothing) from this option.
  The memory consumption inflicted by both write_concurrency and read_concurrency is a constant overhead per table for set, bag and duplicate_bag when the true alternative for the write_concurrency option is not used. For all tables with the auto alternative and ordered_set tables with true alternative the memory overhead depends on the amount of actual detected concurrency during runtime. The memory overhead can be especially large when both write_concurrency and read_concurrency are combined.
  if you need to change the write_concurrency use the following syntax: `[write_concurrency: true]` or `[write_concurrency: :auto]`

  #### Decentralized Counters
  From ETS documentation:
  Performance tuning. Defaults to true for all tables with the write_concurrency option set to auto. For tables of type ordered_set the option also defaults to true when the write_concurrency option is set to true. The option defaults to false for all other configurations. This option has no effect if the write_concurrency option is set to false.
  When this option is set to true, the table is optimized for frequent concurrent calls to operations that modify the tables size and/or its memory consumption (e.g., insert/2 and delete/2). The drawback is that calls to info/1 and info/2 with size or memory as the second argument can get much slower when the decentralized_counters option is turned on.
  When this option is enabled the counters for the table size and memory consumption are distributed over several cache lines and the scheduling threads are mapped to one of those cache lines. The erl option +dcg can be used to control the number of cache lines that the counters are distributed over.
  if you need to change the decentralized_counters use the following syntax: `[decentralized_counters: true]`

  """
  alias ActiveMemory.Adapter.Helpers

  defmacro __using__(opts) do
    quote do
      import ActiveMemory.Table, only: [attributes: 1, attributes: 2]

      @primary_key nil
      @timestamps_opts []
      @foreign_key_type :uuid
      @attributes_context nil
      @field_source_mapper fn x -> x end

      Module.register_attribute(__MODULE__, :active_memory_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_query_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_field_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_autogenerate, accumulate: true)
      Module.put_attribute(__MODULE__, :active_memory_autogenerate_uuid, nil)

      opts = unquote(Macro.expand(opts, __CALLER__))

      table_type = Keyword.get(opts, :type, :mnesia)

      table_options = Keyword.get(opts, :options, :defaults)

      Module.put_attribute(__MODULE__, :adapter, Helpers.set_adapter(table_type))

      Module.put_attribute(
        __MODULE__,
        :table_options,
        Helpers.build_options(table_options, table_type)
      )
    end
  end

  defmacro attributes(opts \\ nil, do: block) do
    define_attributes(opts, block)
  end

  defp define_attributes(opts, block) do
    prelude =
      quote do
        @after_compile ActiveMemory.Table

        Module.register_attribute(__MODULE__, :active_memory_struct_fields, accumulate: true)

        if @primary_key == nil do
          @primary_key {:uuid, autogenerate: true}
        end

        primary_key_fields =
          case @primary_key do
            false ->
              []

            {name, opts} ->
              ActiveMemory.Table.__field__(
                __MODULE__,
                name,
                [primary_key: true] ++ opts
              )

              [name]

            other ->
              raise ArgumentError, "@primary_key must be false or {name, type, opts}"
          end

        try do
          import ActiveMemory.Table
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        primary_key_fields = @active_memory_primary_keys |> Enum.reverse()
        autogenerate = @active_memory_autogenerate |> Enum.reverse()
        fields = @active_memory_fields |> Enum.reverse()
        active_memory_query_fields = @active_memory_query_fields |> Enum.reverse()
        field_sources = @active_memory_field_sources |> Enum.reverse()
        query_fields = Enum.map(active_memory_query_fields, & &1)
        query_map = Helpers.build_query_map(query_fields)

        loaded = ActiveMemory.Table.__loaded__(__MODULE__, @active_memory_struct_fields)

        defstruct Enum.reverse(@active_memory_struct_fields)

        def __attributes__(:fields), do: unquote(Enum.map(fields, & &1))

        def __attributes__(:query_fields), do: unquote(query_fields)

        def __attributes__(:primary_key), do: unquote(primary_key_fields)

        def __attributes__(:query_map), do: unquote(query_map)

        def __attributes__(:autogenerate_uuid),
          do: unquote(Macro.escape(@active_memory_autogenerate_uuid))

        def __attributes__(:adapter), do: unquote(Macro.escape(@adapter))

        def __attributes__(:table_options), do: unquote(Macro.escape(@table_options))

        def __attributes__(:autogenerate), do: unquote(Macro.escape(autogenerate))

        def __attributes__(:loaded), do: unquote(Macro.escape(loaded))

        def __attributes__(:match_head),
          do:
            Helpers.build_match_head(
              unquote(query_map),
              unquote(__MODULE__),
              unquote(Macro.escape(@adapter))
            )

        for clauses <-
              ActiveMemory.Table.__attributes__(
                fields,
                field_sources
              ),
            {args, body} <- clauses do
          def __attributes__(unquote_splicing(args)), do: unquote(body)
        end
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  defmacro field(name, opts \\ []) do
    quote do
      ActiveMemory.Table.__field__(
        __MODULE__,
        unquote(name),
        unquote(opts)
      )
    end
  end

  @doc false
  def __field__(mod, name, opts) do
    define_field(mod, name, opts)
  end

  @doc false
  def __loaded__(module, struct_fields) do
    Map.new([{:__struct__, module} | struct_fields])
  end

  @doc false
  def __after_compile__(%{module: _module}, _) do
    :ok
  end

  @doc false
  def __attributes__(fields, field_sources) do
    load =
      for name <- fields do
        if alias = field_sources[name] do
          {name, {:source, alias}}
        else
          name
        end
      end

    dump =
      for name <- fields do
        {name, field_sources[name] || name}
      end

    field_sources_quoted =
      for name <- fields do
        {[:field_source, name], field_sources[name] || name}
      end

    single_arg = [
      {[:dump], dump |> Map.new() |> Macro.escape()},
      {[:load], load |> Macro.escape()}
    ]

    catch_all = [
      {[:field_source, quote(do: _)], nil}
    ]

    [
      single_arg,
      field_sources_quoted,
      catch_all
    ]
  end

  defp define_field(mod, name, opts) do
    pk? = Keyword.get(opts, :primary_key) || false
    put_struct_field(mod, name, Keyword.get(opts, :default))

    if pk? do
      Module.put_attribute(mod, :active_memory_primary_keys, name)
    end

    if Keyword.get(opts, :load_in_query, true) do
      Module.put_attribute(mod, :active_memory_query_fields, name)
    end

    Module.put_attribute(mod, :active_memory_fields, name)
  end

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :active_memory_struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError,
            "field/association #{inspect(name)} already exists on schema, you must either remove the duplication or choose a different name"
    end

    Module.put_attribute(mod, :active_memory_struct_fields, {name, assoc})
  end
end
