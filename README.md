<h1 style="color: green">ActiveMemory</h1>

## **The typed, attribute-queryable in-memory store for ETS and Mnesia**

## Overview 

In most applications, a huge share of database load is reads of data that barely changes: **reference data** (countries, currencies, tax tables), **configuration** (feature flags, plans, tenant settings), **authorization** (admin users, roles, permissions), and **catalog data** (products, pricing, shipping classes). Every request re-asks the database questions whose answers changed last Tuesday.

ActiveMemory exists to take that load off the database: load those tables into memory **once at boot**, serve every read *for those tables* from RAM, and write back only when something actually changes. For those datasets the database simply disappears from the hot request path, and the connection pool is freed for queries that earn their round trip.

It's a cache with no cache to manage — no keys to design, no TTLs on data that shouldn't expire, no cold misses, no invalidation dance. The in-memory copy serves the reads, while the database remains the durable source of truth.

The reason plain ETS isn't enough is that this data gets read by **attribute**, not by key:

```elixir
# auth check that used to hit the database on every request
AdminStore.one(%{email: email, active?: true})

# product lookups, by any combination of fields
ProductStore.select(%{category: "electronics", in_stock?: true})

# atomically claim a one-time token — exactly one concurrent caller wins
TokenStore.withdraw(%{value: submitted_token})
```

Define a `Table` and you get typed structs queryable by any combination of fields — no ETS match specs to hand-write. And since 0.8.0 a table can literally be an Ecto `embedded_schema` that happens to live entirely in memory: the same Ecto-flavored interface runs on ETS or Mnesia, with built-in [boot-time seeding](#seeding), [record expiry (TTL)](#expiry-ttl), [crash resilience](#resilience), and [atomic take-once reads](#store-api).

ActiveMemory abstracts the ETS and Mnesia specifics behind a common interface called a [`Store`](#store-api), or an [`ActiveRepo`](#multiple-tables-with-an-activerepo) when you need multiple tables.

### When to reach for ActiveMemory

| You need | Reach for |
|---|---|
| To cache computed values by key, with eviction policies and hit/miss stats | A cache: [Cachex](https://github.com/whitfin/cachex), [Nebulex](https://github.com/elixir-nebulex/nebulex) |
| Durable, relational data | A database with [Ecto](https://github.com/elixir-ecto/ecto) |
| Raw ETS speed with access patterns you fully control, no schema layer | [`:ets`](https://www.erlang.org/doc/apps/stdlib/ets.html) directly |
| Shared state for services **outside** your BEAM cluster | [Redis](https://redis.io)/Valkey |
| **Structured records in memory, queried by their attributes** | **ActiveMemory** |

The sweet spot is any small-to-medium dataset that is read constantly but changes rarely — reference data, configuration, authorization, catalog data — plus short-lived records that benefit from TTL and atomic take-once reads, like one-time tokens and 2FA codes. See [Potential Use Cases](#potential-use-cases).

#### Why not Redis?
If the state only exists to serve your application, a Redis round trip costs a network hop, serialization, and an infrastructure dependency — for data that could live in the same memory as the code using it. An ETS read is an in-process memory access; even localhost Redis is orders of magnitude away. Where Redis genuinely earns its place is state shared with things that are not your BEAM cluster, or state that must outlive it. For sharing *within* a cluster, a replicated Mnesia table covers many cases — see [Running on more than one node](#running-on-more-than-one-node-and-surviving-a-partition) for the trade-offs, which are real.

#### Why not `:ets` directly?
You always can — ActiveMemory is ETS/Mnesia underneath, and raw `:ets` is the right call when you control the access patterns and want zero overhead. What the schema layer buys: typed structs instead of tuples, queries on any attribute without hand-written match specs, changeset validation, TTL, a supervised lifecycle, and a table that survives its owner crashing. The cost is the translation layer on each operation; if you are counting microseconds on a hot path, measure both.

#### Why not Mnesia directly (or [memento](https://github.com/sheharyarn/memento))?
Mnesia's power comes wrapped in an API from 1999 — records, match specs, transaction ceremony — and memento wraps that nicely for Mnesia specifically. ActiveMemory gives one API across **both** backends, so a table can start on ETS and move to replicated Mnesia by changing one option, and adds what neither has built in: Ecto changeset integration, TTL expiry, and atomic take-once reads (`withdraw/1`). The Mnesia-specific options are still there when you need them — passed through, not hidden.

## Example setup
1. Define a `Table` with attributes.
2. Define a `Store` or an `ActiveRepo` with configuration settings or accept the defaults (most applications should be fine with defaults). 
3. Add the `Store` or `ActiveRepo` to your application supervision tree.

Your app is ready!

Example Table:
```elixir
defmodule MyApp.People.Person do
  use ActiveMemory.Table,
    options: [index: [:last, :cylon?]]

  attributes do
    field(:email)
    field(:first)
    field(:last)
    field(:hair_color)
    field(:age)
    field(:cylon?)
  end
end

There is also optional auto-generation of uuid

  attributes auto_generate_uuid: true do
    field(:email)
    field(:first)
    field(:last)
    field(:hair_color)
    field(:age)
    field(:cylon?)
  end
```
Example Mnesia Store (default):
```elixir
defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person
end
```
Example ETS Store:
```elixir
defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    type: :ets
end
```

Add the `Store` to your application supervision tree:
```elixir
defmodule MyApp.Application do
  # code..
  def start(_type, _args) do
    children = [
      # other children
      MyApp.People.Store,
      # other children
    ]
    # code..
  end
end
```

Now you have the default `Store` methods available!

## Field types and Ecto Changesets
Fields accept an optional [Ecto type](https://hexdocs.pm/ecto/Ecto.Schema.html#module-types-and-casting) (defaulting to `:any` when omitted). Types are not enforced by the table itself — ETS and Mnesia store any term — they power `Ecto.Changeset` casting and validation, which works directly on the table struct:

```elixir
defmodule MyApp.Planet do
  use ActiveMemory.Table, type: :ets

  attributes auto_generate_uuid: true do
    field(:name, :string)
    field(:gravity, :float)
    field(:moons, :integer, default: 0)
  end
end

{:ok, planet} =
  %MyApp.Planet{}
  |> Ecto.Changeset.cast(params, [:name, :gravity, :moons])
  |> Ecto.Changeset.validate_required([:name])
  |> MyApp.Planet.Store.write()
```

`write/1` accepts a changeset directly, the way `c:Ecto.Repo.insert/2` does — no `Ecto.Changeset.apply_changes/1` step of your own. This works the same on a `Store` and on an [`ActiveRepo`](#activerepo-api), which infers the table from the changeset's data. An invalid changeset is returned as `{:error, changeset}` with its `action` set to `:insert`, so a Phoenix form renders the errors:

```elixir
def create_planet(attrs) do
  %MyApp.Planet{}
  |> MyApp.Planet.changeset(attrs)
  |> MyApp.Planet.Store.write()
end
```

## Using an Ecto schema as a Table
A table can skip the `attributes` block entirely and define an Ecto `embedded_schema`. All table metadata is derived from the schema, and since the module is a real Ecto schema every changeset function works out of the box:

```elixir
defmodule MyApp.Comet do
  use ActiveMemory.Table, type: :ets

  use Ecto.Schema

  embedded_schema do
    field(:name, :string)
    field(:orbit_years, :integer)
  end
end
```

Autogenerated fields are honored: `write/1` fills any field the schema declares as autogenerated when it is still `nil`. That covers the default `embedded_schema` primary key (an autogenerated `binary_id`), an explicit uuid key such as `@primary_key {:uuid, Ecto.UUID, autogenerate: true}`, and `timestamps()`. An autogenerated *integer* primary key cannot be generated in memory and raises when the table is created.

With `@primary_key false` the first declared field becomes the table key. Virtual fields are never stored, and a table with a `ttl` must declare its own `field(:expires_at, :integer)`. See the `ActiveMemory.Table` docs for details.

## Store API
- `Store.all/1` Get all records stored, optionally ordered and paged — see [Reading, counting, ordering](#reading-counting-ordering)
- `Store.count/1` Count the records stored without reading them (O(1))
- `Store.delete/1` Delete the record provided, matched in full — see [Deleting a record](#deleting-a-record)
- `Store.delete_all/0` Delete all records stored
- `Store.exists?/2` Whether any record matches an attributes search or `match` query
- `Store.get/1` and `Store.get!/1` Get the record with the given primary key; the bang variant raises `ActiveMemory.NotFoundError`
- `Store.get_by/1` and `Store.get_by!/1` Get the single record matching an attributes search
- `Store.one/1` Get one record matching either an attributes search or `match` query. Raises `ActiveMemory.MultipleResultsError` when several match, as `c:Ecto.Repo.one/2` does
- `Store.one!/1` Like `one/1` but raises `ActiveMemory.NotFoundError`
- `Store.reload/1` and `Store.reload!/1` Re-read a record by its primary key
- `Store.select/2` Get all records matching either an attributes search or `match` query, optionally ordered and paged
- `Store.withdraw/1` Atomically get one record matching either an attributes search or `match` query, delete the record and return it. The find-and-delete is a single atomic operation (`:ets.select_delete/2` for ETS, a `:mnesia.transaction/1` for Mnesia), so under concurrent access exactly one caller receives `{:ok, record}` for a given record and any others receive `{:error, :not_found}`. This makes `withdraw/1` safe for take-once workloads such as one time use tokens.
- `Store.write/1` Write a record into the memory table. Takes a struct or an `Ecto.Changeset`; an invalid changeset is returned as `{:error, changeset}` with its `action` set, exactly like `c:Ecto.Repo.insert/2`

## Reading, counting, ordering
Reads by primary key, and the counts, come out the way an Ecto user expects. The primary key is the table's first field — `:uuid` on a table using `auto_generate_uuid: true`, an Ecto schema's declared key, or the first field declared:

```elixir
{:ok, person} = Store.get(uuid)
person = Store.get!(uuid)                    # raises ActiveMemory.NotFoundError
{:ok, person} = Store.get_by(%{email: email})

Store.count()                                 # O(1): asks the table for its size
Store.exists?(%{active?: true})
{:ok, person} = Store.reload(stale_person)    # re-read by key
```

A query meant to find one record that matches several raises `ActiveMemory.MultipleResultsError` from `one/1`, `one!/1`, `get_by/1` and `get_by!/1`, exactly as `c:Ecto.Repo.one/2` does. Use `select/2` when many records are expected.

Ordering and paging are options on the reads:

```elixir
Store.all(order_by: :last, limit: 20)
Store.all(order_by: [{:desc, :age}, :last], offset: 20, limit: 20)
Store.select(%{cylon?: true}, order_by: :last)
```

Neither ETS nor Mnesia can order a result, so this sorts after reading — `O(n log n)` over the matched records, not an index backed sort. `:limit` and `:offset` are **convenience pagination, not indexed pagination**: every matched record is read and sorted before the offset is thrown away, so `offset: 10_000, limit: 10` pays for all 10,010. Without an `:order_by` the order is whatever the table gives back, which for a `:set` table is unspecified. Values are compared with their own `compare/2` when they have one, so `Decimal`, `DateTime`, `NaiveDateTime`, `Date` and `Time` fields sort correctly rather than by Erlang term order.

> **`count/1` on a `ttl` table**
>
> The count comes from the table itself, so it includes records that have expired but have not been swept yet and can exceed what the reads return. Pass `sweep: true` to delete those first and get a count that agrees with the reads. `exists?/2` takes the option too, though its answer never depends on it — reads already ignore an expired record.

## Deleting a record
`delete/1` — on a `Store` or an [`ActiveRepo`](#activerepo-api) — removes an **exact** record match: the struct you pass is compared field for field against what is stored (`:ets.delete_object/2`, `:mnesia.delete_object/3`).

> **⚠️ A stale struct deletes nothing, and still returns `:ok`**
>
> Pass a struct that has diverged from the stored copy — a stale read, or one you modified in memory — and no record is removed, yet the call returns `:ok`: the same answer `delete/1` gives for a record that was never there. Deleting is idempotent and never reports whether a record was present.
>
> This is deliberate. Full record matching is the only correct behavior for a `:bag` table, where several records share a key, and on a `:set` table it means a delete never clobbers a newer version of a record written since you read it.
>
> When you hold an identifier rather than a record you know is current, use `withdraw/1` (`withdraw/2` on an `ActiveRepo`). It matches on a query, so staleness cannot affect it, it is atomic, and it reports what happened:
>
> ```elixir
> case MyApp.People.Store.withdraw(%{uuid: uuid}) do
>   {:ok, person} -> # removed, and here is the record that was stored
>   {:error, :not_found} -> # nothing matched
> end
> ```

## Concurrency
Both a `Store` and an `ActiveRepo` are `GenServer`s, but the data functions (`all`, `one`, `select`, `write`, `delete`, `delete_all`, `withdraw`) are **not** routed through that process and are **not** serialized by it. They are ordinary module functions that run in the **caller's** process and delegate straight to the table's adapter, so reads and writes execute with `:ets`/`:mnesia` concurrency — many processes operate in parallel and the single `GenServer` is **not** a bottleneck. Only lifecycle and metadata operations (`init`, `state`, `reload_seeds`) actually use the `GenServer`.

These functions live on the `GenServer` module purely for **organization**: it is the single place responsible for how the application talks to its table(s), following the Single Responsibility Principle. See the [S.T.O.N.E principles](https://www.hpt-consulting.org/blog/stone-principles) for the broader design philosophy.

## Query interface
This is where ActiveMemory earns its keep: records are found by their **attributes**, not by a key you had to design up front. Any field — or any combination of fields — is queryable. There are two query styles.
### The Attribute query syntax
Attribute matching allows you to provide a map of any subset of the table's fields to search by.
```elixir
Store.one(%{uuid: "a users uuid"})
Store.select(%{department: "accounting", admin?: false, active: true})
```
### The `match` query syntax
When equality isn't enough, the `match` macro adds comparisons and boolean logic.
```elixir
query = match(:department == "sales" or :department == "marketing" and :start_date > last_month)
Store.select(query)
```
Expressing either of these with a key/value cache would mean maintaining your own secondary indexes by hand; here the table's schema makes every field queryable for free.
## Seeding
When starting a `Store` there is an option to provide a valid seed file and have the `Store` auto load seeds contained in the file.
```elixir
defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    seed_file: Path.expand("person_seeds.exs", __DIR__)
end
```

## Before `init`
All stores are `GenServers` and have `init` functions. While those are abstracted you can still specify methods to run during the `init` phase of the GenServer startup. Use the `before_init` keyword and add the methods as tuples with the arguments.
```elixir
defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    before_init: [{:run_me, ["arg1", "arg2", ...]}, {:run_me_too, []}]
end
```

> **⚠️ `before_init` and table recovery**
>
> For ETS stores the table is preserved across a store crash/restart by the table heir (see [Resilience](#resilience)). On such a recovery seed files are **not** re-run, but `before_init` methods **always** run, including on recovery. If a `before_init` method writes records with unique or generated keys (for example a `uuid`), running it again on recovery can create duplicates.
>
> How to handle this is left to the implementer. One option is to make any `before_init` write follow a "find or create" pattern — check with `one/1` before calling `write/1` — so the method is idempotent across restarts:
>
> ```elixir
> def run_me(args) do
>   record = build_record(args)
>
>   case one(%{key: record.key}) do
>     {:ok, existing} -> {:ok, existing}
>     {:error, :not_found} -> write(record)
>   end
> end
> ```

##  Initial State
All stores are `GenServers` and thus have a state. The default state is an array as such:
```elixir
%{started_at: "date time when first started", table_name: MyApp.People.Store}
```
This default state can be overwritten with a new state structure or values by supplying a method and arguments as a tuple to the keyword `initial_state`.

```elixir
defmodule MyApp.People.Store do
  use ActiveMemory.Store,
    table: MyApp.People.Person,
    initial_state: {:initial_state_method, ["arg1", "arg2", ...]}
end
```

## Resilience
An ETS table is owned by the process that creates it, so if a `Store` were to crash the table — and all of its data — would normally be destroyed and recreated empty when the supervisor restarts the `Store`.

`ActiveMemory` guards against this automatically. The library starts a small, stable process, `ActiveMemory.TableHeir`, and registers it as the ETS [`:heir`](https://www.erlang.org/doc/man/ets.html#new-2) for every table a `Store` creates. When a `Store` process terminates, ETS transfers the table to the heir instead of destroying it. When the supervisor restarts the `Store`, it reclaims the table from the heir with the data intact.

This requires **no configuration and no API changes**: the heir is started as part of the `:active_memory` application, and the `Store` functions behave exactly as before. When the heir is not running, stores fall back to creating a fresh table.

```elixir
# A store crashes...               the table survives (held by the heir)
# ...the supervisor restarts it...  the store reclaims the table, data intact
```

A few things to be aware of:
- **Seeds are skipped on recovery.** A recovered table already holds its data, so a configured `seed_file` is not re-run. `before_init` methods, however, always run — see the warning in [Before `init`](#before-init).
- **Mnesia stores are unaffected.** Mnesia tables are owned by the Mnesia subsystem rather than the `Store` process, so they already survive a `Store` crash; the heir is purely an ETS concern.
- **Scope is process crashes, not node restarts.** The heir protects against `Store` crashes and supervisor restarts. It does **not** protect against a full node/BEAM restart, which clears all ETS regardless. For data that must survive a restart, use a Mnesia store with `disc_copies`.

## Running on more than one node (and surviving a partition)
An ETS table is node-local: each node has its own, and nothing is shared. A Mnesia table can be replicated across nodes with `ram_copies`/`disc_copies`, which is where network partitions become a concern.

Mnesia's partition behavior is the most common reason teams walk away from it, and the mitigation is one table option that is **off by default**:

```elixir
defmodule MyApp.Sessions.Session do
  use ActiveMemory.Table,
    options: [
      majority: true,
      ram_copies: [:"node1@host", :"node2@host", :"node3@host"]
    ]

  attributes do
    field(:token, :string)
    field(:user_id, :integer)
  end
end
```

`majority: true` requires a **majority of that table's replicas to be reachable before a transactional write commits**. On the minority side of a partition writes are aborted instead of accepted, so the two sides do not silently diverge.

**Why the default hurts.** With `majority: false`, each side of a partition keeps accepting writes against its own replicas. Mnesia does not merge conflicting histories, and it does not stop you from creating them. When the nodes reconnect and each has logged the other as down, Mnesia emits an `{inconsistent_database, running_partitioned_network, node}` system event — and the default handler **logs an error and carries on**, serving whichever replica a given node reads from.

That is deliberate: there is no correct automatic merge without knowing what the data means. But it means divergence is not loud, and recovery is operator work — choose an authoritative replica with [`:mnesia.set_master_nodes/1,2`](https://www.erlang.org/doc/apps/mnesia/mnesia.html#set_master_nodes/1) and restart the nodes that should resynchronise from it, or restore from a backup.

**What it costs.**
- Writes on the minority side fail: availability traded for consistency.
- You want an **odd** number of replicas. With two, neither side of a split holds a majority and writes stop on both.
- It gates **updates**, not reads. ActiveMemory's Mnesia reads run in a transaction but commit nothing, so they still succeed on the minority side and return that replica's contents — which may be behind the majority's.
- It is per table, so one table can opt in without changing the rest.

**If that is not enough.** Quorum writes reduce divergence; they do not make Mnesia partition tolerant. If the data genuinely cannot tolerate a partition, keep the system of record in a database and treat the ActiveMemory table as derived, or reach for a consensus backed store such as [Khepri](https://hexdocs.pm/khepri) when the data model suits a leader and quorum. Khepri is not a drop-in for arbitrary Mnesia tables — it is a tree structured store built for strongly consistent state, and the RabbitMQ team adopted it for their metadata rather than as a general replacement.

**On a single node none of this applies.** The only replica is always a majority, so `majority: true` adds no availability constraint.

## Expiry (TTL)
Give a `Table` a `ttl` (time-to-live, in milliseconds) and its records expire automatically — ideal for the one-time tokens, 2FA codes, magic links and short-lived API keys in [Potential Use Cases](#potential-use-cases).

```elixir
defmodule MyApp.Tokens.Token do
  use ActiveMemory.Table,
    type: :ets,
    ttl: :timer.hours(1)

  attributes do
    field(:token)
    field(:user_id)
  end
end
```

A `ttl` adds an `expires_at` field (appended last, so it never becomes the table key) and stamps it on each write as `now + ttl`. Expiry is then enforced in two complementary ways:

- **Lazy filter on read** — `one`, `select`, `all` and `withdraw` never return an expired record. This is immediate and exact: a record is unreadable the instant it expires.
- **Periodic sweep** — the owning `Store`/`ActiveRepo` deletes expired records on a timer to reclaim memory. The cadence defaults to one minute and is configurable per process:

```elixir
use ActiveMemory.Store, table: MyApp.Tokens.Token, sweep_interval: :timer.seconds(30)
```

Notes:
- The sweep only runs when a table declares a `ttl`; non-TTL tables are untouched and incur zero overhead.
- `expires_at` is plain data, so it survives [`Resilience`](#resilience) recovery — TTL keeps working after a crash.
- Works the same for `:ets` and `:mnesia`, and for both a `Store` and an `ActiveRepo` (where each table can have its own `ttl`).

## Multiple tables with an ActiveRepo
A `Store` manages a single `Table`. When you want one supervised entry point over **several** tables, use an `ActiveMemory.ActiveRepo` — the multi-table counterpart to a `Store`. (It is named `ActiveRepo` rather than `Repo` so it does not collide with an application's `Ecto.Repo`.)

```elixir
defmodule MyApp.ActiveRepo do
  use ActiveMemory.ActiveRepo,
    tables: [
      MyApp.People.Person,
      {MyApp.Dogs.Dog, seed_file: Path.expand("dog_seeds.exs", __DIR__), before_init: [{:warm, []}]}
      ..other Table
    ]
end
```

Add it to your supervision tree like any other process (`children = [MyApp.ActiveRepo]`). Tables may freely mix `:ets` and `:mnesia`; each call dispatches to the adapter configured on the given table.

### ActiveRepo API
Every operation a [`Store`](#store-api) offers is available on an `ActiveRepo`, with the same behavior — only the arities differ. Reads and `withdraw` take the table module as the first argument, while `write` and `delete` infer the table from the struct (or from a changeset's data):
```elixir
MyApp.ActiveRepo.write(%Person{...})          # table inferred from the struct
MyApp.ActiveRepo.write(Person.changeset(%Person{}, attrs))  # or from a changeset
MyApp.ActiveRepo.withdraw(Dog, query)         # reads take the table explicitly
MyApp.ActiveRepo.all(Person)
MyApp.ActiveRepo.one(Dog, %{name: "gem"})
MyApp.ActiveRepo.select(Person, query)
MyApp.ActiveRepo.delete(%Dog{} = dog)
MyApp.ActiveRepo.delete_all(Person)
```
- `ActiveRepo.all/2` Get all records stored in a table, optionally ordered and paged
- `ActiveRepo.count/2` Count the records in a table without reading them (O(1))
- `ActiveRepo.delete/1` Delete the record provided, matched in full — see [Deleting a record](#deleting-a-record)
- `ActiveRepo.delete_all/1` Delete all records stored in a table
- `ActiveRepo.exists?/3` Whether any record in a table matches an attributes search or `match` query
- `ActiveRepo.get/2` and `ActiveRepo.get!/2` Get the record with the given primary key
- `ActiveRepo.get_by/2` and `ActiveRepo.get_by!/2` Get the single record in a table matching an attributes search
- `ActiveRepo.one/2` Get one record from a table matching either an attributes search or `match` query. Raises `ActiveMemory.MultipleResultsError` when several match
- `ActiveRepo.one!/2` Like `one/2` but raises `ActiveMemory.NotFoundError`
- `ActiveRepo.reload/1` and `ActiveRepo.reload!/1` Re-read a record by its primary key, inferring the table
- `ActiveRepo.select/3` Get all records from a table matching either an attributes search or `match` query, optionally ordered and paged
- `ActiveRepo.withdraw/2` Atomically get one record from a table matching either an attributes search or `match` query, delete the record and return it — the same take-once guarantee as `Store.withdraw/1`
- `ActiveRepo.write/1` Write a record into its table. Takes a struct or an `Ecto.Changeset`; an invalid changeset is returned as `{:error, changeset}` with its `action` set, exactly like `c:Ecto.Repo.insert/2`
- An operation for a struct or table that is not part of the `ActiveRepo` returns `{:error, :unknown_table}`.

### Per-table options
Each `tables:` entry is a table module or a `{table, opts}` tuple. Per-table `seed_file` and `before_init` work exactly as they do for a `Store`; `initial_state` is an `ActiveRepo`-level option (one process, one state). Seeding, the [query interface](#query-interface) and [Resilience](#resilience) all behave the same as for a `Store` — including the [`before_init` recovery caveat](#before-init).

## Testing
A table's module name **is** its ETS/Mnesia table name, and a `Store` registers itself under its own module name. So isolation between tests comes down to whether they share a table.

### Tests that own their table can be `async: true`
Give a test module its own table and store and it runs concurrently with every other test module, no configuration required:

```elixir
defmodule MyApp.CacheTest.Table do
  use ActiveMemory.Table, type: :ets

  attributes do
    field(:key, :string)
    field(:value, :string)
  end
end

defmodule MyApp.CacheTest.Store do
  use ActiveMemory.Store, table: MyApp.CacheTest.Table
end

defmodule MyApp.CacheTest do
  use ExUnit.Case, async: true

  alias MyApp.CacheTest.{Store, Table}

  setup_all do
    {:ok, _pid} = Store.start_link()

    on_exit(fn ->
      case :ets.whereis(Table) do
        :undefined -> :ok
        _ref -> :ets.delete(Table)
      end
    end)

    :ok
  end

  setup do
    :ok = Store.delete_all()
  end

  test "stores a value" do
    {:ok, _record} = Store.write(%Table{key: "a", value: "1"})
    assert {:ok, %Table{value: "1"}} = Store.get("a")
  end
end
```

Tests **within** a module always run sequentially, so a `setup` calling `delete_all/0` is enough to isolate them from each other.

### Tests that share your application's store need `async: false`
Testing a context function that reaches for your application's singleton store — `MyApp.Planets.create_planet/1` writing through `MyApp.Planets.Store` — means every such test module writes to the same global table. Two of them running concurrently will see each other's records, so mark those modules `async: false`:

```elixir
defmodule MyApp.PlanetsTest do
  # shares MyApp.Planets.Store with the rest of the app
  use ExUnit.Case, async: false

  setup do
    :ok = MyApp.Planets.Store.delete_all()
  end

  # ...
end
```

This is the one case ActiveMemory cannot isolate for you yet. A sandbox that gives each test process its own table is on the roadmap for 0.9.0 — see [Planned Enhancements](#planned-enhancements). Until then, code written to take its store as an argument or read it from configuration can be tested with the `async: true` pattern above.

### Mnesia tables in tests
Mnesia tables are owned by the Mnesia subsystem rather than the `Store`, so clean them up with `:mnesia.delete_table/1` instead of `:ets.delete/1`. Running `mix test --no-start` (as this project does) keeps the application from starting its own stores while the suite manages them.

## Installation

The package can be installed
by adding `active_memory` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:active_memory, "~> 0.8.0"}
  ]
end
```

Check out the [documentation on hexdocs](https://hexdocs.pm/active_memory), the [Coming from Ecto](https://hexdocs.pm/active_memory/coming_from_ecto.html) guide, and the [changelog](https://hexdocs.pm/active_memory/changelog.html).

### Upgrading from 0.7
Two behavior changes in 0.8.0 can require code updates:

1. **`one/1` and `withdraw/1` raise `ActiveMemory.MultipleResultsError`** when a query matches more than one record, instead of returning `{:error, :more_than_one_result}` — matching `c:Ecto.Repo.one/2`. Update any caller matching on that tuple; a query that legitimately matches many records should use `select/2`.
2. **An Ecto schema table whose declared primary key is not its first field, or is composite, raises when the table is created.** The first field is the physical table key, so the previous behavior would have read the wrong field.

See the [changelog](https://hexdocs.pm/active_memory/changelog.html) for the full list.

## Potential Use Cases
The common thread: data that is expensive to keep asking the database for, but changes rarely enough that a resident in-memory copy makes sense. Several of these are hit on **every authenticated request** — roles and permissions, tenant settings, feature flags, plan entitlements — and can account for multiple database queries before an application starts its real work.

### Products, plans, and reference data
Catalog data (products, SKUs, pricing tiers, shipping classes), subscription plans and their entitlements, and static reference tables (countries, currencies, tax codes) are read on nearly every request and change on human timescales. Load them from the database at boot with a `before_init` function, serve every lookup from memory, and write back through the store when they change.

### Admin users, roles, and permissions
Authorization data is checked constantly and edited rarely. Keep admins, role mappings, and permission matrices in a store so auth checks never queue for a database connection.

### Storing config settings and Application secrets
Instead of having hard coded secrets and application settings crowding your config files store them in an in memory table. Provide your application a small UI to support the secrets and settings and you can update while the application is running in a matter of seconds.

### One Time Use Tokens 
Perfect for short lived tokens such as password reset tokens, 2FA tokens, magic links (password less login) etc. Store the tokens along with any other needed data into an `ActiveMemory.Store` to reduce the burden of your database and provide your users a better experience with faster responses. Use `Store.withdraw/1` to redeem a token: it atomically fetches and deletes the record, so even under concurrent requests a token can only be redeemed once.

### API Keys for clients
For applications which have a fixed set of API Keys or a relativly small set of API keys (less than a few thousand). Store the keys along with any relevent information into an `ActiveMemory.Store` to reduce the burden of your database and provide your users a better experience with faster responses.

### JWT Encryption Keys
Applications using JWT's can store the keys in an `ActiveMemory.Store` and provide fast access for encrypting JWT's and fast access for publishing the public keys on an endpoint for token verification by consuming clients.

**and many many many more...**

## Demo Application
A demo application built on the current release — showing catalog data served from memory instead of the database, one-time tokens with `withdraw/1` and `ttl`, and feature flags — is in progress and will be linked here. Until then, the [Coming from Ecto](https://hexdocs.pm/active_memory/coming_from_ecto.html) guide has complete, current examples.

## Planned Enhancements

### 0.9.0 — safe to keep
0.8.0 made ActiveMemory easy to start; 0.9.0 makes it safe to keep — under concurrent tests, growing tables, and concurrent writers.

- **Test isolation.** A sandbox (`ActiveMemory.Test`) giving each test process its own table, so test modules that share your application's store can run `async: true`. Test modules that own their table already run concurrently today — see [Testing](#testing) — but a context test writing through the app's singleton store cannot be isolated yet, because a table's module name is its physical table name.
- **Secondary indexes the reads use.** Attribute queries are full scans today, and the Mnesia `index:` option builds indexes no read path consults — writes pay for maintenance, reads get nothing. Shadow index tables for ETS, `:mnesia.index_read/3` for Mnesia, so querying by attribute stays fast as tables grow. Also what makes `order_by` and pagination affordable.
- **`update/1` and atomic counters.** `write/1` is a whole-record upsert, so concurrent field updates are last-write-wins and `updated_at` never refreshes. An `update/1` that requires the record to exist, plus an `update_counter`-style atomic increment (`:ets.update_counter/3`) — which unlocks rate limiting as a use case.
- **Telemetry.** `[:active_memory, :write | :one | :select | :withdraw]` events with duration, table, and result, so the usual observability tooling can see the library.
- **Introspection and memory bounds.** `Store.info/0` (record count, memory bytes) and a documented story for tables that grow unbounded — today a `ttl` is the only limit.
- **Cluster tests in CI.** The distributed migration tests are currently excluded; `local_cluster` 2.x (`:peer` based) makes running them cheap. Includes fixing the `create_table` retry loop when a configured replica node is permanently unreachable, and partition tests documenting behavior with and without `majority: true`.

### Exploring
Ideas under consideration once 0.9.0 lands — feedback welcome:

- A replicated, partition-safe backend (Raft based, e.g. [Khepri](https://hexdocs.pm/khepri)) alongside ETS and Mnesia, for tables that must stay consistent across nodes.
- Reactive reads — subscribe to changes on a table without polling.
- Write-behind sync to an external store (a database or Redis) for durability and cold starts, keeping reads at memory speed.

Any suggestions appreciated.
