defmodule ActiveMemory.Table do
  @moduledoc """

  Define your table attributes and defaults just like a regular Elixir module struct.
  Keys can have default values defined.

  Example Table:
  ```elixir
  defmodule MyApp.People.Person do
  use ActiveMemory.Table attributes: [
    :uuid, 
    :email, 
    :first_name,
    :last_name,
    :department,
    :start_date,
    :active,
    :admin?
    complex: %{more: "complex", keys: "can be used", with: "defaults"}
  ]
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
    attributes: [:name, :breed, :weight, fixed?: true, nested: %{one: nil, default: true}],
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
      import unquote(__MODULE__)

      opts = unquote(Macro.expand(opts, __CALLER__))

      @struct_attrs Keyword.get(opts, :attributes)
      @table_type Keyword.get(opts, :type, :mnesia)
      @adapter Helpers.set_adapter(@table_type)
      @query_map Helpers.build_query_map(@struct_attrs)
      @table_options Keyword.get(opts, :options, :defaults)

      defstruct @struct_attrs

      def __meta__,
        do: %{
          adapter: @adapter,
          attributes: Helpers.build_struct_keys(@struct_attrs),
          match_head: Helpers.build_match_head(@query_map, __MODULE__, @table_type),
          query_map: @query_map,
          table_options: Helpers.build_options(@table_options, @table_type)
        }

      def adapter, do: @adapter
    end
  end
end
