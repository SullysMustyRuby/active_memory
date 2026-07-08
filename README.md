<h1 style="color: green">ActiveMemory</h1>

## **The typed, attribute-queryable in-memory store for ETS and Mnesia**

## Overview 

A key/value cache answers one question: *"what is the value for this key?"* ActiveMemory answers the questions a cache cannot:

```elixir
# every active session for a user
SessionStore.select(%{user_id: user_id, active?: true})

# admins who have not logged in since the cutoff
StaffStore.select(match(:role == "admin" and :last_login < cutoff))

# atomically claim a one-time token — exactly one concurrent caller wins
TokenStore.withdraw(%{value: submitted_token})
```

Define a `Table` with named attributes and you get typed structs you can query by **any combination of fields** — no cache keys to design, no ETS match specs to hand-write, no database round-trip. The same simple ORM interface runs on ETS or Mnesia, with built-in [record expiry (TTL)](#expiry-ttl), [crash resilience](#resilience), and [atomic take-once reads](#store-api).

ActiveMemory abstracts the ETS and Mnesia specifics behind a common interface called a [`Store`](#store-api), or an [`ActiveRepo`](#multiple-tables-with-an-activerepo) when you need multiple tables.

### When to reach for ActiveMemory

| You need | Reach for |
|---|---|
| To cache computed values by key, with eviction policies and hit/miss stats | A cache: [Cachex](https://github.com/whitfin/cachex), [Nebulex](https://github.com/elixir-nebulex/nebulex) |
| Durable, relational data | A database with [Ecto](https://github.com/elixir-ecto/ecto) |
| **Structured records in memory, queried by their attributes** | **ActiveMemory** |

The sweet spot is any small-to-medium dataset you would be tempted to put in a database table but want at memory speed: one-time tokens and 2FA codes, sessions, feature flags and config, API keys, reference data. See [Potential Use Cases](#potential-use-cases).

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

## Store API
- `Store.all/0` Get all records stored
- `Store.delete/1` Delete the record provided
- `Store.delete_all/0` Delete all records stored
- `Store.one/1` Get one record matching either an attributes search or `match` query
- `Store.select/1` Get all records matching either an attributes search or `match` query
- `Store.withdraw/1` Atomically get one record matching either an attributes search or `match` query, delete the record and return it. The find-and-delete is a single atomic operation (`:ets.select_delete/2` for ETS, a `:mnesia.transaction/1` for Mnesia), so under concurrent access exactly one caller receives `{:ok, record}` for a given record and any others receive `{:error, :not_found}`. This makes `withdraw/1` safe for take-once workloads such as one time use tokens.
- `Store.write/1` Write a record into the memmory table

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
Reads and `withdraw` take the table module as the first argument; writes and deletes infer the table from the struct:
```elixir
MyApp.ActiveRepo.write(%Person{...})          # table inferred from the struct
MyApp.ActiveRepo.withdraw(Dog, query)         # reads take the table explicitly
MyApp.ActiveRepo.all(Person)
MyApp.ActiveRepo.one(Dog, %{name: "gem"})
MyApp.ActiveRepo.select(Person, query)
MyApp.ActiveRepo.delete(%Dog{} = dog)
MyApp.ActiveRepo.delete_all(Person)
```
- `ActiveRepo.all/1`, `ActiveRepo.delete/1`, `ActiveRepo.delete_all/1`, `ActiveRepo.one/2`, `ActiveRepo.select/2`, `ActiveRepo.withdraw/2`, `ActiveRepo.write/1`
- An operation for a struct or table that is not part of the `ActiveRepo` returns `{:error, :unknown_table}`.

### Per-table options
Each `tables:` entry is a table module or a `{table, opts}` tuple. Per-table `seed_file` and `before_init` work exactly as they do for a `Store`; `initial_state` is an `ActiveRepo`-level option (one process, one state). Seeding, the [query interface](#query-interface) and [Resilience](#resilience) all behave the same as for a `Store` — including the [`before_init` recovery caveat](#before-init).

## Installation

The package can be installed
by adding `active_memory` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:active_memory, "~> 0.7.0"}
  ]
end
```

Check out the ([documentation](https://hex.pm/packages/active_memory))

## Potential Use Cases
There are many reasons to be leveraging the power of in memory store and the awesome tools of [Mnesia](https://www.erlang.org/doc/man/mnesia.html) and [ETS](https://www.erlang.org/doc/man/ets.html) in your Elixir applications.

### Storing config settings and Application secrets
Instead of having hard coded secrets and application settings crowding your config files store them in an in memory table. Provide your application a small UI to support the secrets and settings and you can update while the application is running in a matter of seconds.

### One Time Use Tokens 
Perfect for short lived tokens such as password reset tokens, 2FA tokens, magic links (password less login) etc. Store the tokens along with any other needed data into an `ActiveMemory.Store` to reduce the burden of your database and provide your users a better experience with faster responses. Use `Store.withdraw/1` to redeem a token: it atomically fetches and deletes the record, so even under concurrent requests a token can only be redeemed once.

### API Keys for clients
For applications which have a fixed set of API Keys or a relativly small set of API keys (less than a few thousand). Store the keys along with any relevent information into an `ActiveMemory.Store` to reduce the burden of your database and provide your users a better experience with faster responses.

### JWT Encryption Keys
Applications using JWT's can store the keys in an `ActiveMemory.Store` and provide fast access for encrypting JWT's and fast access for publishing the public keys on an endpoint for token verification by consuming clients.

### Admin User Management
Create an `ActiveMemory.Store` to manage your admins easily and safely. 

**and many many many more...**

## Demo Application
The following Repo is a demo application using ActiveMemory and MnesiaManager concept.
- [BeamDemo](https://github.com/SullysMustyRuby/BeamDemo)
- [MnesiaManager](https://github.com/SullysMustyRuby/ActiveMemoryManager)

## Planned Enhancements
- Allow pass through `:ets` and `mnesia` options for table creation
- Allow pass through `:ets` and `mnesia` syntax for searches
- Mnesia co-ordination with Docker instance for backup and disk persistance
- Enhance `match` query syntax
  - Select option for certain fields
  - Group results

Any suggestions appreciated.
