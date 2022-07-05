<h1 style="color: green">ActiveMemory</h1>

## **A Simple ORM for ETS and Mnesia**

<h4 style="color: red">Please note!</h4> 
<p style="color: red">This is still a work in progess and feedback is appreciated</p>

## Overview 

A package to help bring the power of in memory storage with ETS and Mnesia to your Elixir application. 

ActiveMemory provides a simple interface and configuration which abstracts the ETS and Mnesia specifics and provides a common interface called a `Store`.

## Example setup
1. Define a `Table` with attributes.
2. Define a `Store` with configuration settings or accept the defaults (most applications should be fine with defaults). 
3. Add the `Store` to your application supervision tree.

Your app is ready!

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
  ]
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
- `Store.withdraw/1` Get one record matching either an attributes search or `match` query, delete the record and return it
- `Store.write/1` Write a record into the memmory table

## Query interface
There are two different query types available to help make finding the records in your store easier. 
### The Attribute query syntax
Attribute matching allows you to provide a map of attributes to search by.
```elixir
Store.one(%{uuid: "a users uuid"})
Store.select(%{department: "accounting", admin?: false, active: true})
```
### The `match` query syntax
Using the `match` macro you can structure a basic query.  
```elixir
query = match(:department == "sales" or :department == "marketing" and :start_date > last_month)
Store.select(query)
```
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

## Installation

The package can be installed
by adding `active_memory` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:active_memory, "~> 0.1.0"}
  ]
end
```

## Potential Use Cases
There are many reasons to be leveraging the power of in memory store and the awesome tools of [Mnesia](https://www.erlang.org/doc/man/mnesia.html) and [ETS](https://www.erlang.org/doc/man/ets.html) in your Elixir applications.

### Storing config settings and Application secrets
Instead of having hard coded secrets and application settings crowding your config files store them in an in memory table. Provide your application a small UI to support the secrets and settings and you can update while the application is running in a matter of seconds.

### One Time Use Tokens 
Perfect for short lived tokens such as password reset tokens, 2FA tokens, magic links (password less login) etc. Store the tokens along with any other needed data into an `ActiveMemory.Store` to reduce the burden of your database and provide your users a better experience with faster responses.

### API Keys for clients
For applications which have a fixed set of API Keys or a relativly small set of API keys (less than a few thousand). Store the keys along with any relevent information into an `ActiveMemory.Store` to reduce the burden of your database and provide your users a better experience with faster responses.

### JWT Encryption Keys
Applications using JWT's can store the keys in an `ActiveMemory.Store` and provide fast access for encrypting JWT's and fast access for publishing the public keys on an endpoint for token verification by consuming clients.

### Admin User Management
Create an `ActiveMemory.Store` to manage your admins easily and safely. 

**and many many many more...**


## Planned Enhancements
- Allow pass through `:ets` and `mnesia` options for table creation
- Allow pass through `:ets` and `mnesia` syntax for searches
- Mnesia co-ordination with Docker instance for backup and disk persistance
- Enhance `match` query syntax
  - Select option for certain fields
  - Group results

Any suggestions appreciated.
