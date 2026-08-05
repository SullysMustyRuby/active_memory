defmodule Test.Support.Ecto.NoExpiry do
  use ActiveMemory.Table,
    type: :ets,
    ttl: :timer.seconds(1)

  use Ecto.Schema

  embedded_schema do
    field(:token, :string)
  end
end

defmodule Test.Support.Ecto.Expiring do
  use ActiveMemory.Table,
    type: :ets,
    ttl: 25

  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:code, :string)
    field(:expires_at, :integer)
  end
end

# A uuid named primary key with an `Ecto.UUID` type, the shape a project carries
# over from an `auto_generate_uuid: true` attributes table. Ecto reports this
# through `__schema__(:autogenerate)` rather than `__schema__(:autogenerate_id)`.
defmodule Test.Support.Ecto.UuidKey do
  use Ecto.Schema
  use ActiveMemory.Table, type: :ets

  @primary_key {:uuid, Ecto.UUID, autogenerate: true}
  embedded_schema do
    field(:name, :string)
    field(:gravity, :decimal)
  end
end

defmodule Test.Support.Ecto.Stamped do
  use Ecto.Schema
  use ActiveMemory.Table, type: :ets

  @primary_key {:uuid, Ecto.UUID, autogenerate: true}
  embedded_schema do
    field(:name, :string)
    timestamps()
  end
end

defmodule Test.Support.Ecto.IntegerKey do
  use Ecto.Schema
  use ActiveMemory.Table, type: :ets

  @primary_key {:id, :id, autogenerate: true}
  embedded_schema do
    field(:name, :string)
  end
end

defmodule ActiveMemory.EctoSchemaTableTest do
  use ExUnit.Case, async: false

  import ActiveMemory.Query

  alias ActiveMemory.Adapters.{Ets, Mnesia}
  alias ActiveMemory.Operations
  alias Ecto.Changeset
  alias Test.Support.Comets.Comet
  alias Test.Support.Comets.Store, as: CometStore
  alias Test.Support.Ecto.Expiring
  alias Test.Support.Ecto.IntegerKey
  alias Test.Support.Ecto.NoExpiry
  alias Test.Support.Ecto.Stamped
  alias Test.Support.Ecto.UuidKey
  alias Test.Support.Moons.Moon
  alias Test.Support.Moons.Store, as: MoonStore
  alias Test.Support.ProcessHelper

  describe "table metadata derived from the Ecto schema" do
    test "for an ets table with the default primary key" do
      assert Comet.__attributes__(:adapter) == Ets
      assert Comet.__attributes__(:query_fields) == [:id, :name, :orbit_years, :tail?]
      assert Comet.__attributes__(:autogenerate) == [{[:id], {Ecto.UUID, :autogenerate, []}}]
      assert Comet.__attributes__(:auto_generate_uuid) == false
      assert Comet.__attributes__(:ttl) == nil

      assert Comet.__attributes__(:types) == %{
               id: :binary_id,
               name: :string,
               orbit_years: :integer,
               tail?: :boolean
             }

      assert Comet.__attributes__(:query_map) == [
               id: :"$1",
               name: :"$2",
               orbit_years: :"$3",
               tail?: :"$4"
             ]

      assert Comet.__attributes__(:match_head) == {:"$1", :"$2", :"$3", :"$4"}
    end

    test "for a mnesia table without a primary key" do
      assert Moon.__attributes__(:adapter) == Mnesia
      assert Moon.__attributes__(:query_fields) == [:name, :planet, :radius_km]
      assert Moon.__attributes__(:autogenerate) == []
      assert Moon.__attributes__(:match_head) == {Moon, :"$1", :"$2", :"$3"}
    end

    test "field defaults from the schema are applied" do
      assert %Comet{}.tail? == true
    end
  end

  describe "an ets store on an Ecto schema table" do
    setup do
      ProcessHelper.stop(CometStore)
      {:ok, pid} = CometStore.start_link()

      on_exit(fn ->
        ProcessHelper.stop(CometStore)

        case :ets.whereis(Comet) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Comet)
        end
      end)

      {:ok, %{pid: pid}}
    end

    test "write autogenerates the binary_id primary key" do
      assert {:ok, %Comet{id: id}} = CometStore.write(%Comet{name: "Halley", orbit_years: 76})
      assert {:ok, ^id} = Ecto.UUID.cast(id)
    end

    test "write keeps a preset primary key" do
      id = Ecto.UUID.generate()

      assert {:ok, %Comet{id: ^id}} = CometStore.write(%Comet{id: id, name: "Hale-Bopp"})
    end

    test "map queries and match queries work" do
      {:ok, halley} = CometStore.write(%Comet{name: "Halley", orbit_years: 76})
      {:ok, _encke} = CometStore.write(%Comet{name: "Encke", orbit_years: 3})

      assert {:ok, ^halley} = CometStore.one(%{name: "Halley"})
      assert {:ok, [^halley]} = CometStore.select(match(:orbit_years > 50))
    end

    test "delete and delete_all work" do
      {:ok, halley} = CometStore.write(%Comet{name: "Halley", orbit_years: 76})

      assert CometStore.delete(halley) == :ok
      assert CometStore.one(%{name: "Halley"}) == {:error, :not_found}

      {:ok, _encke} = CometStore.write(%Comet{name: "Encke", orbit_years: 3})

      assert CometStore.delete_all() == :ok
      assert CometStore.all() == []
    end

    test "changesets cast and validate with no extra definitions" do
      {:ok, comet} =
        %Comet{}
        |> Changeset.cast(%{"name" => "Halley", "orbit_years" => "76"}, [:name, :orbit_years])
        |> Changeset.validate_required([:name])
        |> Changeset.apply_action(:insert)

      assert {:ok, %Comet{id: id, orbit_years: 76}} = CometStore.write(comet)
      assert is_binary(id)
    end
  end

  describe "a mnesia store on an Ecto schema table" do
    setup do
      ProcessHelper.stop(MoonStore)
      {:ok, pid} = MoonStore.start_link()

      on_exit(fn ->
        ProcessHelper.stop(MoonStore)
        :mnesia.delete_table(Moon)
      end)

      {:ok, %{pid: pid}}
    end

    test "write, query, and delete round trip" do
      assert {:ok, luna} =
               MoonStore.write(%Moon{name: "Luna", planet: "Earth", radius_km: 1737.4})

      assert {:ok, ^luna} = MoonStore.one(%{planet: "Earth"})
      assert {:ok, [^luna]} = MoonStore.select(match(:radius_km > 1000))

      assert MoonStore.delete(luna) == :ok
      assert MoonStore.all() == []
    end

    test "the first schema field is the table key" do
      {:ok, _io} = MoonStore.write(%Moon{name: "Io", planet: "Jupiter", radius_km: 1.0})
      {:ok, _io} = MoonStore.write(%Moon{name: "Io", planet: "Jupiter", radius_km: 1821.6})

      assert [%Moon{radius_km: 1821.6}] = MoonStore.all()
    end
  end

  describe "ttl on an Ecto schema table" do
    test "stamps and enforces expiry through the declared expires_at field" do
      {:ok, :created} = Operations.create_table(Expiring)

      on_exit(fn ->
        case :ets.whereis(Expiring) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Expiring)
        end
      end)

      {:ok, written} = Operations.write(%Expiring{code: "abc"}, Expiring)

      assert is_integer(written.expires_at)
      assert {:ok, ^written} = Operations.one(%{code: "abc"}, Expiring)

      Process.sleep(50)

      assert Operations.one(%{code: "abc"}, Expiring) == {:error, :not_found}
    end

    test "a ttl table without an expires_at field raises at table creation" do
      assert_raise ArgumentError, ~r/no :expires_at field/, fn ->
        Operations.create_table(NoExpiry)
      end
    end
  end

  describe "a uuid named Ecto.UUID primary key" do
    setup do
      {:ok, :created} = Operations.create_table(UuidKey)

      on_exit(fn ->
        case :ets.whereis(UuidKey) do
          :undefined -> :ok
          _table_ref -> :ets.delete(UuidKey)
        end
      end)

      :ok
    end

    test "is reported as autogenerated" do
      assert UuidKey.__attributes__(:autogenerate) == [{[:uuid], {Ecto.UUID, :autogenerate, []}}]
    end

    test "is generated on write" do
      {:ok, written} = Operations.write(%UuidKey{name: "Mars"}, UuidKey)

      assert {:ok, _uuid} = Ecto.UUID.cast(written.uuid)
      assert {:ok, ^written} = Operations.one(%{uuid: written.uuid}, UuidKey)
    end

    test "each record gets a distinct key rather than collapsing onto nil" do
      {:ok, mars} = Operations.write(%UuidKey{name: "Mars"}, UuidKey)
      {:ok, venus} = Operations.write(%UuidKey{name: "Venus"}, UuidKey)

      refute is_nil(mars.uuid)
      refute mars.uuid == venus.uuid
      assert length(Operations.all(UuidKey)) == 2
    end

    test "a preset key is kept" do
      uuid = Ecto.UUID.generate()

      assert {:ok, %UuidKey{uuid: ^uuid}} =
               Operations.write(%UuidKey{uuid: uuid, name: "Mars"}, UuidKey)
    end

    test "a decimal field round trips" do
      gravity = Decimal.new("3.71")

      {:ok, written} = Operations.write(%UuidKey{name: "Mars", gravity: gravity}, UuidKey)

      assert {:ok, %UuidKey{gravity: ^gravity}} = Operations.one(%{name: "Mars"}, UuidKey)
      assert written.gravity == gravity
    end
  end

  describe "timestamps() on an Ecto schema table" do
    setup do
      {:ok, :created} = Operations.create_table(Stamped)

      on_exit(fn ->
        case :ets.whereis(Stamped) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Stamped)
        end
      end)

      :ok
    end

    test "are stamped on write" do
      {:ok, written} = Operations.write(%Stamped{name: "Mars"}, Stamped)

      assert %NaiveDateTime{} = written.inserted_at
      assert %NaiveDateTime{} = written.updated_at
    end

    test "a preset timestamp is kept" do
      inserted_at = ~N[2020-01-01 00:00:00]

      {:ok, written} =
        Operations.write(%Stamped{name: "Mars", inserted_at: inserted_at}, Stamped)

      assert written.inserted_at == inserted_at
    end
  end

  describe "an autogenerated integer primary key" do
    test "raises at table creation because it cannot be generated in memory" do
      assert_raise ArgumentError, ~r/cannot autogenerate the :id primary key/, fn ->
        Operations.create_table(IntegerKey)
      end
    end
  end

  describe "a table with neither attributes nor an Ecto schema" do
    test "raises at compile time" do
      assert_raise ArgumentError, ~r/defines no fields/, fn ->
        defmodule NoFields do
          use ActiveMemory.Table, type: :ets
        end
      end
    end
  end
end
