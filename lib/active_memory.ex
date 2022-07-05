defmodule ActiveMemory do
  @moduledoc """
  Bring the power of in memory storage with ETS and Mnesia to your Elixir application. 

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
  ```

  """
end
