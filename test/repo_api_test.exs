defmodule Test.Support.Api.Listing do
  use Ecto.Schema
  use ActiveMemory.Table, type: :ets

  @primary_key {:uuid, Ecto.UUID, autogenerate: true}
  embedded_schema do
    field(:name, :string)
    field(:gravity, :decimal)
    field(:moons, :integer)
    timestamps()
  end
end

# An Ecto schema whose declared key is not the first field: the first field is the
# table key, so this cannot be honored.
defmodule Test.Support.Api.MisplacedKey do
  use Ecto.Schema
  use ActiveMemory.Table, type: :ets

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:id, :binary_id, primary_key: true)
  end
end

defmodule Test.Support.Api.CompositeKey do
  use Ecto.Schema
  use ActiveMemory.Table, type: :ets

  @primary_key false
  embedded_schema do
    field(:left, :string, primary_key: true)
    field(:right, :string, primary_key: true)
  end
end

defmodule ActiveMemory.RepoApiTest do
  use ExUnit.Case, async: false

  alias ActiveMemory.MultipleResultsError
  alias ActiveMemory.NotFoundError
  alias ActiveMemory.Operations
  alias Test.Support.Api.CompositeKey
  alias Test.Support.Api.Listing
  alias Test.Support.Api.MisplacedKey
  alias Test.Support.Comets.Comet
  alias Test.Support.Comets.Store, as: CometStore
  alias Test.Support.Moons.Moon
  alias Test.Support.Moons.Store, as: MoonStore
  alias Test.Support.Planets.Planet
  alias Test.Support.Planets.Store, as: PlanetStore
  alias Test.Support.ProcessHelper
  alias Test.Support.Ttl.Token
  alias Test.Support.Ttl.TokenStore

  defp start_store(store, table) do
    ProcessHelper.stop(store)
    {:ok, _pid} = store.start_link()

    on_exit(fn ->
      ProcessHelper.stop(store)

      case :ets.whereis(table) do
        :undefined -> :ok
        _table_ref -> :ets.delete(table)
      end
    end)

    :ok
  end

  defp start_table(table) do
    {:ok, :created} = Operations.create_table(table)

    on_exit(fn ->
      case :ets.whereis(table) do
        :undefined -> :ok
        _table_ref -> :ets.delete(table)
      end
    end)

    :ok
  end

  describe "__attributes__(:primary_key)" do
    test "is the uuid on an attributes table using auto_generate_uuid" do
      assert Planet.__attributes__(:primary_key) == :uuid
    end

    test "is the declared key on an Ecto schema table" do
      assert Comet.__attributes__(:primary_key) == :id
      assert Listing.__attributes__(:primary_key) == :uuid
    end

    test "is the first field when the schema declares no key" do
      assert Moon.__attributes__(:primary_key) == :name
    end

    test "raises when the declared key is not the first field" do
      assert_raise ArgumentError,
                   ~r/is the first field, and the first field is the table key/,
                   fn ->
                     Operations.create_table(MisplacedKey)
                   end
    end

    test "raises for a composite primary key" do
      assert_raise ArgumentError, ~r/composite primary key/, fn ->
        Operations.create_table(CompositeKey)
      end
    end
  end

  describe "count/1" do
    setup do: start_store(PlanetStore, Planet)

    test "counts without reading the records" do
      assert PlanetStore.count() == 0

      {:ok, _mars} = PlanetStore.write(%Planet{name: "Mars"})
      {:ok, _venus} = PlanetStore.write(%Planet{name: "Venus"})

      assert PlanetStore.count() == 2
    end
  end

  describe "count/1 on a ttl table" do
    setup do: start_store(TokenStore, Token)

    test "includes expired records unless a sweep is asked for" do
      {:ok, _token} = TokenStore.write(%Token{name: "magic", value: "abc"})

      assert TokenStore.count() == 1

      Process.sleep(75)

      # The record is expired but not swept: reads hide it, the raw count does not.
      assert TokenStore.all() == []
      assert TokenStore.count() == 1
      assert TokenStore.count(sweep: true) == 0
    end
  end

  describe "exists?/2" do
    setup do: start_store(PlanetStore, Planet)

    test "reports whether anything matches" do
      refute PlanetStore.exists?(%{name: "Mars"})

      {:ok, _mars} = PlanetStore.write(%Planet{name: "Mars"})

      assert PlanetStore.exists?(%{name: "Mars"})
      refute PlanetStore.exists?(%{name: "Pluto"})
    end

    test "is true when several match" do
      {:ok, _a} = PlanetStore.write(%Planet{name: "Mars", moons: 2})
      {:ok, _b} = PlanetStore.write(%Planet{name: "Mars", moons: 2})

      assert PlanetStore.exists?(%{name: "Mars"})
    end

    test "is false for a query the schema does not have" do
      refute PlanetStore.exists?(%{nonsense: true})
    end
  end

  describe "get/1 and get!/1" do
    setup do: start_store(PlanetStore, Planet)

    test "reads by primary key" do
      {:ok, mars} = PlanetStore.write(%Planet{name: "Mars"})

      assert {:ok, ^mars} = PlanetStore.get(mars.uuid)
      assert PlanetStore.get!(mars.uuid) == mars
    end

    test "returns not_found for an absent key" do
      assert PlanetStore.get(Ecto.UUID.generate()) == {:error, :not_found}
    end

    test "get!/1 raises NotFoundError naming the table" do
      uuid = Ecto.UUID.generate()

      assert_raise NotFoundError, ~r/no record found in .*Planet/, fn ->
        PlanetStore.get!(uuid)
      end
    end
  end

  describe "get/1 on an Ecto schema table" do
    setup do: start_store(CometStore, Comet)

    test "reads by the schema's key" do
      {:ok, halley} = CometStore.write(%Comet{name: "Halley"})

      assert {:ok, ^halley} = CometStore.get(halley.id)
    end
  end

  describe "get_by/1 and get_by!/1" do
    setup do: start_store(PlanetStore, Planet)

    test "reads by an attributes map" do
      {:ok, mars} = PlanetStore.write(%Planet{name: "Mars", moons: 2})

      assert {:ok, ^mars} = PlanetStore.get_by(%{name: "Mars"})
      assert PlanetStore.get_by!(%{name: "Mars"}) == mars
    end

    test "returns not_found when nothing matches" do
      assert PlanetStore.get_by(%{name: "Pluto"}) == {:error, :not_found}

      assert_raise NotFoundError, fn -> PlanetStore.get_by!(%{name: "Pluto"}) end
    end

    test "raises when several match, as Ecto does" do
      {:ok, _a} = PlanetStore.write(%Planet{name: "Mars", moons: 1})
      {:ok, _b} = PlanetStore.write(%Planet{name: "Mars", moons: 2})

      assert_raise MultipleResultsError, ~r/Use select\/1/, fn ->
        PlanetStore.get_by(%{name: "Mars"})
      end
    end
  end

  describe "one!/1" do
    setup do: start_store(PlanetStore, Planet)

    test "returns the record or raises" do
      {:ok, mars} = PlanetStore.write(%Planet{name: "Mars"})

      assert PlanetStore.one!(%{name: "Mars"}) == mars
      assert_raise NotFoundError, fn -> PlanetStore.one!(%{name: "Pluto"}) end
    end
  end

  describe "reload/1 and reload!/1" do
    setup do: start_store(PlanetStore, Planet)

    test "re-reads a stale struct by key" do
      {:ok, mars} = PlanetStore.write(%Planet{name: "Mars", moons: 1})
      {:ok, updated} = PlanetStore.write(%{mars | moons: 2})

      stale = mars

      assert {:ok, ^updated} = PlanetStore.reload(stale)
      assert PlanetStore.reload!(stale).moons == 2
    end

    test "returns not_found when the record is gone" do
      {:ok, mars} = PlanetStore.write(%Planet{name: "Mars"})
      :ok = PlanetStore.delete(mars)

      assert PlanetStore.reload(mars) == {:error, :not_found}
      assert_raise NotFoundError, fn -> PlanetStore.reload!(mars) end
    end

    test "returns bad_schema for a struct from another table" do
      assert PlanetStore.reload(%Comet{name: "Halley"}) == {:error, :bad_schema}
    end
  end

  describe "ordering and paging" do
    setup do: start_table(Listing)

    setup do
      for {name, gravity, moons} <- [
            {"Venus", "8.87", 0},
            {"Earth", "9.807", 1},
            {"Mars", "3.71", 2}
          ] do
        {:ok, _record} =
          Operations.write(
            struct(Listing, %{name: name, gravity: Decimal.new(gravity), moons: moons}),
            Listing
          )
      end

      :ok
    end

    test "orders ascending by a field" do
      names = Operations.all(Listing, order_by: :name) |> Enum.map(& &1.name)

      assert names == ["Earth", "Mars", "Venus"]
    end

    test "orders descending" do
      names = Operations.all(Listing, order_by: {:desc, :name}) |> Enum.map(& &1.name)

      assert names == ["Venus", "Mars", "Earth"]
    end

    test "orders decimals numerically rather than by term order" do
      gravities =
        Operations.all(Listing, order_by: :gravity)
        |> Enum.map(&Decimal.to_string(&1.gravity))

      assert gravities == ["3.71", "8.87", "9.807"]
    end

    test "orders naive datetimes chronologically" do
      # timestamps() are stamped on write, so all three share a second; add a
      # record with an explicit older timestamp to prove the comparison is used.
      {:ok, _old} =
        Operations.write(
          struct(Listing, %{name: "Ancient", inserted_at: ~N[2000-01-01 00:00:00]}),
          Listing
        )

      first = Operations.all(Listing, order_by: :inserted_at) |> List.first()

      assert first.name == "Ancient"
    end

    test "breaks ties with a second key" do
      {:ok, _dup} =
        Operations.write(struct(Listing, %{name: "Mars", moons: 9}), Listing)

      ordered = Operations.all(Listing, order_by: [:name, {:desc, :moons}])
      mars = Enum.filter(ordered, &(&1.name == "Mars")) |> Enum.map(& &1.moons)

      assert mars == [9, 2]
    end

    test "limits and offsets after ordering" do
      assert Operations.all(Listing, order_by: :name, limit: 2) |> Enum.map(& &1.name) ==
               ["Earth", "Mars"]

      assert Operations.all(Listing, order_by: :name, offset: 1) |> Enum.map(& &1.name) ==
               ["Mars", "Venus"]

      assert Operations.all(Listing, order_by: :name, offset: 1, limit: 1)
             |> Enum.map(& &1.name) == ["Mars"]
    end

    test "select/3 takes the same options" do
      {:ok, records} = Operations.select(%{}, Listing, order_by: {:desc, :name}, limit: 1)

      assert Enum.map(records, & &1.name) == ["Venus"]
    end

    test "raises on an invalid order_by" do
      assert_raise ArgumentError, ~r/invalid :order_by/, fn ->
        Operations.all(Listing, order_by: "name")
      end
    end
  end

  describe "the mnesia adapter" do
    setup do
      ProcessHelper.stop(MoonStore)
      {:ok, _pid} = MoonStore.start_link()

      on_exit(fn ->
        ProcessHelper.stop(MoonStore)
        :mnesia.delete_table(Moon)
      end)

      :ok
    end

    test "supports count, get and ordering too" do
      {:ok, luna} = MoonStore.write(%Moon{name: "Luna", planet: "Earth", radius_km: 1737.4})
      {:ok, _io} = MoonStore.write(%Moon{name: "Io", planet: "Jupiter", radius_km: 1821.6})

      assert MoonStore.count() == 2
      assert {:ok, ^luna} = MoonStore.get("Luna")
      assert MoonStore.exists?(%{planet: "Jupiter"})

      assert MoonStore.all(order_by: :name) |> Enum.map(& &1.name) == ["Io", "Luna"]
    end
  end
end
