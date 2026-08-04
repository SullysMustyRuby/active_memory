defmodule ActiveMemory.ChangesetWriteTest do
  use ExUnit.Case, async: false

  alias Ecto.Changeset
  alias Test.Support.Comets.Comet
  alias Test.Support.Comets.Store, as: CometStore
  alias Test.Support.Multi.Gadget
  alias Test.Support.Multi.Repo, as: MultiRepo
  alias Test.Support.Multi.Widget
  alias Test.Support.Planets.Planet
  alias Test.Support.Planets.Store, as: PlanetStore
  alias Test.Support.ProcessHelper

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

  describe "Store.write/1 with a valid changeset" do
    setup do: start_store(PlanetStore, Planet)

    test "applies the changeset and writes the struct" do
      changeset =
        Changeset.cast(%Planet{}, %{"name" => "Mars", "gravity" => "3.71"}, [:name, :gravity])

      assert {:ok, %Planet{name: "Mars", gravity: 3.71} = planet} = PlanetStore.write(changeset)
      assert {:ok, ^planet} = PlanetStore.one(%{name: "Mars"})
    end

    test "still autogenerates the uuid" do
      changeset = Changeset.cast(%Planet{}, %{"name" => "Venus"}, [:name])

      assert {:ok, %Planet{uuid: uuid}} = PlanetStore.write(changeset)
      assert {:ok, ^uuid} = Ecto.UUID.cast(uuid)
    end

    test "an empty changeset writes the unchanged struct" do
      changeset = Changeset.cast(%Planet{name: "Pluto"}, %{}, [:name])

      assert {:ok, %Planet{name: "Pluto"}} = PlanetStore.write(changeset)
    end
  end

  describe "Store.write/1 with an invalid changeset" do
    setup do: start_store(PlanetStore, Planet)

    test "returns the changeset without writing" do
      changeset =
        %Planet{}
        |> Changeset.cast(%{"name" => "Mars"}, [:name])
        |> Changeset.validate_required([:gravity])

      assert {:error, %Changeset{} = returned} = PlanetStore.write(changeset)
      refute returned.valid?
      assert [gravity: {"can't be blank", _meta}] = returned.errors
      assert PlanetStore.all() == []
    end

    test "sets action to :insert so a form renders the errors" do
      changeset =
        %Planet{}
        |> Changeset.cast(%{"gravity" => "not a float"}, [:gravity])
        |> Changeset.validate_required([:name])

      assert {:error, %Changeset{action: :insert}} = PlanetStore.write(changeset)
    end
  end

  describe "Store.write/1 with a changeset on an Ecto schema table" do
    setup do: start_store(CometStore, Comet)

    test "writes and autogenerates the primary key" do
      changeset =
        Changeset.cast(%Comet{}, %{"name" => "Halley", "orbit_years" => "76"}, [
          :name,
          :orbit_years
        ])

      assert {:ok, %Comet{id: id, name: "Halley", orbit_years: 76}} = CometStore.write(changeset)
      assert {:ok, ^id} = Ecto.UUID.cast(id)
    end

    test "an invalid changeset is returned" do
      changeset =
        %Comet{}
        |> Changeset.cast(%{"orbit_years" => "not a number"}, [:orbit_years])

      assert {:error, %Changeset{action: :insert, valid?: false}} = CometStore.write(changeset)
      assert CometStore.all() == []
    end
  end

  describe "Store.write/1 with a changeset on a ttl table" do
    alias Test.Support.Ttl.Token
    alias Test.Support.Ttl.TokenStore

    setup do: start_store(TokenStore, Token)

    test "stamps expires_at and the record still expires" do
      changeset =
        Changeset.cast(%Token{}, %{"name" => "magic", "value" => "abc"}, [:name, :value])

      assert {:ok, %Token{expires_at: expires_at}} = TokenStore.write(changeset)
      assert is_integer(expires_at)
      assert {:ok, %Token{name: "magic"}} = TokenStore.one(%{value: "abc"})

      Process.sleep(75)

      assert TokenStore.one(%{value: "abc"}) == {:error, :not_found}
    end
  end

  describe "ActiveRepo.write/1 with a changeset" do
    setup do
      ProcessHelper.stop(MultiRepo)
      {:ok, _pid} = MultiRepo.start_link()

      on_exit(fn ->
        ProcessHelper.stop(MultiRepo)

        case :ets.whereis(Widget) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Widget)
        end

        :mnesia.delete_table(Gadget)
      end)

      MultiRepo.delete_all(Widget)
      MultiRepo.delete_all(Gadget)

      :ok
    end

    test "infers the table from the changeset data" do
      changeset = Changeset.cast(%Widget{}, %{"name" => "x", "color" => "blue"}, [:name, :color])

      assert {:ok, %Widget{name: "x", color: "blue"}} = MultiRepo.write(changeset)
      assert length(MultiRepo.all(Widget)) == 1
      assert MultiRepo.all(Gadget) == []
    end

    test "works for a mnesia backed table too" do
      changeset =
        Changeset.cast(%Gadget{}, %{"name" => "y", "category" => "z"}, [:name, :category])

      assert {:ok, %Gadget{name: "y"}} = MultiRepo.write(changeset)
    end

    test "returns an invalid changeset" do
      changeset =
        %Widget{}
        |> Changeset.cast(%{"name" => "x"}, [:name])
        |> Changeset.validate_required([:color])

      assert {:error, %Changeset{action: :insert, valid?: false}} = MultiRepo.write(changeset)
      assert MultiRepo.all(Widget) == []
    end

    test "a changeset on an unmanaged struct returns :unknown_table" do
      changeset = Changeset.cast({%{name: nil}, %{name: :string}}, %{"name" => "x"}, [:name])

      assert MultiRepo.write(changeset) == {:error, :unknown_table}
    end
  end
end
