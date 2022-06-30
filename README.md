# ActiveMemory

<span style="color:red">
  <h3>This is still a work in progess !!!</h3>
</span>


## **A Simple ORM for ETS and Mnesia**

Bring the power of in memory storage with ETS and Mnesia to your Elixir application. 

ActiveMemory provides a simple interface and configuration which abstracts the ETS and Mnesia specifics and provides a common interface called a `Store`.

## Potential Use Cases
There are many reasons to be leveraging the power of in memory store and the awesome tools of [Mnesia](https://www.erlang.org/doc/man/mnesia.html) and [ETS](https://www.erlang.org/doc/man/ets.html) in your Elixir applications.

### Storing config settings and Application secrets
Instad of having hard coded secrets and application settings crowding your config files store them in an in memory table. Privde your application a small UI to support the secrets and settings and you can update while the application is running in a matter of seconds.

### One Time Use Tokens 
Perfect for short lived tokens such as password reset tokens, 2FA tokens, majic links (passwordless login) etc. Store the tokens and any other needed data into an `ActiveMemory.Store` and reduce the burden of your database and provide your users a better experience with faster responses.

### API Keys
If your application has a small set of API Keys (ex: less than a thousand) for clients accessing your API, then store the keys along with any relavent information into an `ActiveMemory.Store`and reduce the burden of your database and provide your users a better experience with faster responses.

### JWT Encryption Keys
If your application uses JWT then you can store the keys in an `ActiveMemory.Store` and provide fast access for encrypting JWT's and publishing the public keys on an endpoint so consumers can verify the tokens.

### Admin User Management
Create an `ActiveMemory.Store` to manage your admins easily and safely. 

**and many many many more...**

## Example setup
Simply define a `Table` with attributes and type (ETS or Mnesia), then define a `Store` with configuration settings or accept the defaults (most applications should be fine with defaults). Then you are ready!

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
- `Store.delete_all/0` Get all records stored
- `Store.one/1` Get a record matching either an attributes search or `match` query
- `Store.select/1` Get all records matching either attributes search or `match` query
- `Store.withdraw/1` Get a record matching either an attributes search or `match` query, delete the record and return it.
- `Store.write/1` Write the record into the memmory table

## Query interface
There are two different query types availabe to make finding the records in your store. 
### The Attribute query syntax
Attribute matching allows you to provide a map of attributes to search by.
```elixir
Store.one(%{uuid: "a users uuid"})
Store.select(%{department: "accounting", admin?: false, active: true})
```
### The `match` query syntax
Using the `match` macro you can strucure a basic query 
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

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `active_memory` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:active_memory, "~> 0.1.0"}
  ]
end
```


