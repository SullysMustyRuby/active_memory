defmodule ActiveMemory do
  @moduledoc """
  The typed, attribute-queryable in memory store for ETS and Mnesia.

  A key/value cache answers one question: *what is the value for this key?*
  ActiveMemory answers the questions a cache cannot — records are found by their
  **attributes**, in any combination, with no cache keys to design and no ETS match
  specifications to hand write:

  ```elixir
  SessionStore.select(%{user_id: user_id, active?: true})
  StaffStore.select(match(:role == "admin" and :last_login < cutoff))
  TokenStore.withdraw(%{value: submitted_token})
  ```

  The same interface runs on `:ets` or `:mnesia`, with record expiry, crash
  resilience and atomic take-once reads built in.

  ## The pieces

    - `ActiveMemory.Table` — define a table's fields and its ETS/Mnesia options. A
      table is either an `attributes` block or an Ecto `embedded_schema`.
    - `ActiveMemory.Store` — a supervised process owning **one** table, and the API
      you read and write through.
    - `ActiveMemory.ActiveRepo` — the same API over **several** tables from one
      process.
    - `ActiveMemory.Query` — the `match/1` macro, for queries that need more than
      equality.

  ## Getting started

  Define a table, define a store, add the store to your supervision tree.

  ```elixir
  defmodule MyApp.People.Person do
    use ActiveMemory.Table, options: [index: [:last]]

    attributes auto_generate_uuid: true do
      field(:email, :string)
      field(:first, :string)
      field(:last, :string)
      field(:age, :integer)
      field(:admin?, :boolean)
    end
  end

  defmodule MyApp.People.Store do
    use ActiveMemory.Store, table: MyApp.People.Person
  end
  ```

  ```elixir
  # in MyApp.Application
  children = [MyApp.People.Store]
  ```

  That is the whole setup. The table is created when the store starts, so there are
  no migrations to run.

  ```elixir
  {:ok, person} = MyApp.People.Store.write(%MyApp.People.Person{email: "kara@bsg.com"})
  {:ok, person} = MyApp.People.Store.get(person.uuid)
  people = MyApp.People.Store.all(order_by: :last, limit: 20)
  ```

  Tables default to `:mnesia`; pass `type: :ets` for an ETS table. See
  `ActiveMemory.Store` for the full read and write API.

  ## Working with Ecto

  A table takes Ecto types, and can be an Ecto schema outright, so `Ecto.Changeset`
  works on it and `write/1` accepts a changeset the way `c:Ecto.Repo.insert/2` does:

  ```elixir
  %MyApp.People.Person{}
  |> MyApp.People.Person.changeset(params)
  |> MyApp.People.Store.write()
  ```

  The [Coming from Ecto](coming_from_ecto.html) guide covers what carries over, what
  is named differently, and where the two genuinely differ.

  ## What else is built in

    - **Record expiry.** A `ttl` on a table gives every record a lifetime; reads never
      return an expired record and the owning process sweeps them to reclaim memory.
      See `ActiveMemory.Table`.
    - **Crash resilience.** `ActiveMemory.TableHeir` holds ETS tables when a store
      crashes, so the data survives the restart. No configuration needed.
    - **Atomic take-once reads.** `withdraw/1` finds a record and removes it in one
      atomic operation, so exactly one concurrent caller wins — what you want for one
      time tokens and 2FA codes.

  ## Testing

  A table's module name is its ETS/Mnesia table name, so isolation comes down to
  whether tests share a table. A test module that defines its own table and store
  runs `async: true` alongside every other test module with no configuration. Test
  modules that share your application's store need `async: false`, since they write
  to the same global table. See [Testing](readme.html#testing) for both patterns.

  ## When to reach for it

  ActiveMemory suits a small-to-medium dataset you would be tempted to put in a
  database table but want at memory speed: one time tokens, sessions, feature flags
  and config, API keys, reference data.

  It is **not** a system of record. ETS lives and dies with the node, and Mnesia
  persists only with `disc_copies`; keep durable data in a database. For caching
  computed values by key with eviction policies, a cache such as
  [Cachex](https://github.com/whitfin/cachex) or
  [Nebulex](https://github.com/elixir-nebulex/nebulex) is the better fit.

  Running across several nodes means a replicated Mnesia table, which makes network
  partitions a concern — see the `majority` option in `ActiveMemory.Table`.
  """
end
