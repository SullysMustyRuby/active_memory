defmodule ActiveMemory.TableTypesTest do
  use ExUnit.Case, async: false

  alias Ecto.Changeset
  alias Test.Support.Planets.Planet
  alias Test.Support.Planets.Store, as: PlanetStore
  alias Test.Support.ProcessHelper

  describe "__attributes__(:types)" do
    test "returns the declared types, including the auto generated uuid" do
      assert Planet.__attributes__(:types) == %{
               uuid: Ecto.UUID,
               name: :string,
               gravity: :float,
               moons: :integer,
               atmosphere: :any
             }
    end

    test "an untyped field defaults to :any" do
      assert Planet.__attributes__(:types).atmosphere == :any
    end
  end

  describe "__changeset__/0" do
    test "exposes the field types for Ecto.Changeset" do
      assert Planet.__changeset__() == Planet.__attributes__(:types)
    end
  end

  describe "field options" do
    test "defaults are still applied with a typed field" do
      assert %Planet{}.moons == 0
    end
  end

  describe "Ecto.Changeset integration" do
    test "cast uses the declared types" do
      changeset =
        Changeset.cast(%Planet{}, %{"name" => "Mars", "gravity" => "3.71"}, [:name, :gravity])

      assert changeset.valid?
      assert changeset.changes == %{name: "Mars", gravity: 3.71}
    end

    test "cast rejects values that do not match the type" do
      changeset = Changeset.cast(%Planet{}, %{"gravity" => "not a number"}, [:gravity])

      refute changeset.valid?
      assert [gravity: {"is invalid", _meta}] = changeset.errors
    end

    test "validations work on the changeset" do
      changeset =
        %Planet{}
        |> Changeset.cast(%{"gravity" => "3.71"}, [:name, :gravity])
        |> Changeset.validate_required([:name])

      refute changeset.valid?
      assert [name: {"can't be blank", _meta}] = changeset.errors
    end

    test "a cast struct writes to the store" do
      ProcessHelper.stop(PlanetStore)
      {:ok, pid} = PlanetStore.start_link()

      on_exit(fn ->
        ProcessHelper.stop(PlanetStore)

        case :ets.whereis(Planet) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Planet)
        end
      end)

      {:ok, planet} =
        %Planet{}
        |> Changeset.cast(%{"name" => "Venus", "gravity" => "8.87"}, [:name, :gravity])
        |> Changeset.validate_required([:name])
        |> Changeset.apply_action(:insert)

      assert {:ok, %Planet{uuid: uuid, name: "Venus", gravity: 8.87} = written} =
               PlanetStore.write(planet)

      assert {:ok, ^uuid} = Ecto.UUID.cast(uuid)
      assert {:ok, ^written} = PlanetStore.one(%{name: "Venus"})

      Process.exit(pid, :kill)
    end
  end
end
