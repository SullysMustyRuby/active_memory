defmodule ActiveMemory.Adapters.Ets do
  @moduledoc """
  An adapter for storing structs in ETS
  """

  alias ActiveMemory.Adapters.Adapter
  alias ActiveMemory.Adapters.Ets.Helpers
  alias ActiveMemory.Query.{MatchGuards, MatchSpec}
  alias ActiveMemory.TableHeir

  @behaviour Adapter

  @doc """
  Return all structs stored in a table.
  ```elixir
    iex:> DogStore.all(Dog)
    [%Dog{}, %Dog{}]
  ```
  """
  @spec all(atom()) :: list(map())
  def all(table) do
    :ets.tab2list(table)
    |> Task.async_stream(fn record -> to_struct(record, table) end)
    |> Enum.into([], fn {:ok, struct} -> struct end)
  end

  @doc """
  Create a table in ETS using an ActiveMemory.Table.
  This function will take in the ActiveMemory.Table and parse
  the options for the table.
  Example Table (without auto generated uuid):
  ```elixir
    defmodule Test.Support.People.Person do
      use ActiveMemory.Table,
        options: [index: [:last, :cylon?]]

      attributes do
       ...
      end
    end
  ```
  Once the ActiveMemory.Table is defined then the in memory table can be created.
  ```elixir
    iex:> PeopleStore.create_table(Test.Support.People.Person)
    :ok
  ```
  """
  @spec create_table(atom()) :: {:ok, :created | :recovered} | {:error, any()}
  def create_table(table) do
    case :ets.whereis(table) do
      :undefined -> create_new_table(table)
      _table_ref -> recover_table(table)
    end
  end

  @doc """
  Delete a struct from a table.
  ```elixir
    iex:> PeopleStore.delete(%Person{}, Person)
    :ok
  ```
  """
  @spec delete(map(), atom()) :: :ok | {:error, any()}
  def delete(struct, table) do
    with ets_tuple when is_tuple(ets_tuple) <- to_tuple(struct),
         true <- :ets.delete_object(table, ets_tuple) do
      :ok
    else
      _ -> {:error, :delete_failure}
    end
  end

  @doc """
  Delete all structs from a table.
  ```elixir
    iex:> PeopleStore.delete_all(Person)
    true
  ```
  """
  @spec delete_all(atom()) :: true | any()
  def delete_all(table) do
    :ets.delete_all_objects(table)
  end

  @doc """
  Find a single struct in a table using either a map query search or ActiveMemory.Query.MatchSpec.
  using a map query
  ```elixir
    iex:> DogStore.one(%{name: "gem", breed: "Shaggy Black Lab"})
    {:ok, %Dog{}}
  ```
  with ActiveMemory.Query.MatchSpec
  ```elixir
    iex:> DogStore.one(match(:name == "gem" and :breed == "Shaggy Black Lab"))
    {:ok, %Dog{}}
  ```
  """
  @spec one(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def one(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         [record | []] when is_tuple(record) <- match_query(query, table) do
      {:ok, to_struct(record, table)}
    else
      [] -> {:error, :not_found}
      records when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  def one(query, table) when is_tuple(query) do
    with [record | []] when is_tuple(record) <- select_query(query, table) do
      {:ok, to_struct(record, table)}
    else
      [] -> {:error, :not_found}
      records when is_list(records) -> {:error, :more_than_one_result}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  Find a single struct in a table using either a map query search or ActiveMemory.Query.MatchSpec.
  using a map query
  ```elixir
    iex:> DogStore.select(%{name: "gem", breed: "Shaggy Black Lab"})
    {:ok, [%Dog{}, %Dog{}]}
  ```
  with ActiveMemory.Query.MatchSpec
  ```elixir
    iex:> DogStore.select(match(:name == "gem" and :breed == "Shaggy Black Lab"))
    {:ok, [%Dog{}, %Dog{}]}
  ```
  """
  @spec select(map() | tuple(), atom()) :: {:ok, list(map())} | {:error, any()}
  def select(query_map, table) when is_map(query_map) do
    with {:ok, query} <- MatchGuards.build(table, query_map),
         records when is_list(records) <- match_query(query, table) do
      {:ok, to_struct(records, table)}
    else
      [] -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  def select(query, table) when is_tuple(query) do
    with records when is_list(records) <- select_query(query, table) do
      {:ok, to_struct(records, table)}
    else
      [] -> {:ok, []}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  Atomically find a single struct matching the query, delete it, and return it.

  The delete is performed with `:ets.select_delete/2`, so the find-and-remove is a
  single atomic ETS operation. Under concurrent access exactly one caller receives
  `{:ok, struct}` for a given record; any others receive `{:error, :not_found}`.
  ```elixir
    iex:> DogStore.withdraw(%{name: "gem", breed: "Shaggy Black Lab"})
    {:ok, %Dog{}}
  ```
  """
  @spec withdraw(map() | tuple(), atom()) :: {:ok, map()} | {:error, any()}
  def withdraw(query, table) do
    with {:ok, struct} <- one(query, table),
         ets_tuple <- to_tuple(struct),
         count when count >= 1 <- :ets.select_delete(table, [{ets_tuple, [], [true]}]) do
      {:ok, struct}
    else
      0 -> {:error, :not_found}
      {:error, message} -> {:error, message}
    end
  end

  @doc """
  Save a struct to a table.
  ```elixir
    iex:> DogStore.write(%Dog{name: "gem", breed: "Shaggy Black Lab"})
    {:ok, %Dog{}}
  ```
  """
  @spec write(map(), atom()) :: {:ok, map()} | {:error, any()}
  def write(struct, table) do
    with ets_tuple when is_tuple(ets_tuple) <-
           to_tuple(struct),
         true <- :ets.insert(table, ets_tuple) do
      {:ok, struct}
    else
      false -> {:error, :write_fail}
      {:error, message} -> {:error, message}
    end
  end

  defp create_new_table(table) do
    options = table.__attributes__(:table_options)

    try do
      :ets.new(table, [:named_table | heir_options(table) ++ options])
      {:ok, :created}
    rescue
      ArgumentError -> {:error, :create_table_failed}
    end
  end

  defp heir_options(table) do
    case TableHeir.whereis() do
      nil -> []
      heir_pid -> [{:heir, heir_pid, table}]
    end
  end

  defp match_query(query, table) do
    :ets.match_object(table, query)
  end

  defp recover_table(table) do
    with heir_pid when is_pid(heir_pid) <- TableHeir.whereis(),
         :ok <- TableHeir.claim(table) do
      :ets.setopts(table, {:heir, heir_pid, table})
      {:ok, :recovered}
    else
      nil -> {:error, :create_table_failed}
      {:error, :not_held} -> {:error, :create_table_failed}
    end
  end

  defp select_query(query, table) do
    query_map = :erlang.apply(table, :__attributes__, [:query_map])
    match_head = :erlang.apply(table, :__attributes__, [:match_head])

    match_query = MatchSpec.build(query, query_map, match_head)
    :ets.select(table, match_query)
  end

  defp to_struct(records, table) when is_list(records) do
    Enum.into(records, [], fn record -> to_struct(record, table) end)
  end

  defp to_struct(record, table) when is_tuple(record), do: Helpers.to_struct(record, table)

  defp to_tuple(record), do: Helpers.to_tuple(record)
end
