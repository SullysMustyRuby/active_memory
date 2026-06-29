defmodule ActiveMemory.ActiveRepoTest do
  use ExUnit.Case, async: false

  alias ActiveMemory.TableHeir
  alias Test.Support.Multi.Gadget
  alias Test.Support.Multi.Repo, as: MultiRepo
  alias Test.Support.Multi.Widget

  setup_all do
    {:ok, pid} = MultiRepo.start_link()

    on_exit(fn ->
      case Process.whereis(MultiRepo) do
        nil -> :ok
        live -> Process.exit(live, :kill)
      end

      case :ets.whereis(Widget) do
        :undefined -> :ok
        _table_ref -> :ets.delete(Widget)
      end

      :mnesia.delete_table(Gadget)
    end)

    {:ok, %{pid: pid}}
  end

  setup do
    MultiRepo.delete_all(Widget)
    MultiRepo.delete_all(Gadget)

    :ok
  end

  describe "init" do
    test "state lists the managed tables" do
      assert %{started_at: %DateTime{}, tables: tables} = MultiRepo.state()
      assert Widget in tables
      assert Gadget in tables
    end
  end

  describe "write/1 and reads across tables" do
    test "writes and reads an ETS-backed table" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "gizmo", color: "blue"})

      assert {:ok, widget} = MultiRepo.one(Widget, %{name: "gizmo", color: "blue"})
      assert widget.color == "blue"
      assert length(MultiRepo.all(Widget)) == 1
    end

    test "writes and reads a Mnesia-backed table, generating the uuid" do
      {:ok, gadget} = MultiRepo.write(%Gadget{name: "sprocket", category: "tools"})

      assert is_binary(gadget.uuid)
      assert {:ok, found} = MultiRepo.one(Gadget, %{name: "sprocket"})
      assert found.category == "tools"
    end

    test "the two tables are independent" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "w", color: "red"})
      {:ok, _record} = MultiRepo.write(%Gadget{name: "g", category: "c"})

      assert length(MultiRepo.all(Widget)) == 1
      assert length(MultiRepo.all(Gadget)) == 1
    end
  end

  describe "select/2, withdraw/2, delete/1, delete_all/1" do
    test "select returns matching records" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "a", color: "blue"})
      {:ok, _record} = MultiRepo.write(%Widget{name: "b", color: "blue"})

      assert {:ok, widgets} = MultiRepo.select(Widget, %{color: "blue"})
      assert length(widgets) == 2
    end

    test "withdraw fetches and deletes a record" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "gone", color: "blue"})

      assert {:ok, widget} = MultiRepo.withdraw(Widget, %{name: "gone", color: "blue"})
      assert widget.name == "gone"
      assert MultiRepo.one(Widget, %{name: "gone", color: "blue"}) == {:error, :not_found}
    end

    test "delete removes a record, inferring the table from the struct" do
      {:ok, widget} = MultiRepo.write(%Widget{name: "x", color: "blue"})

      assert :ok = MultiRepo.delete(widget)
      assert MultiRepo.all(Widget) == []
    end

    test "delete_all clears a single table" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "x", color: "blue"})
      {:ok, _record} = MultiRepo.write(%Gadget{name: "y", category: "z"})

      MultiRepo.delete_all(Widget)

      assert MultiRepo.all(Widget) == []
      assert length(MultiRepo.all(Gadget)) == 1
    end
  end

  describe "unknown tables" do
    test "reads on an undeclared table return :unknown_table" do
      assert MultiRepo.all(NotManaged) == {:error, :unknown_table}
      assert MultiRepo.one(NotManaged, %{}) == {:error, :unknown_table}
      assert MultiRepo.select(NotManaged, %{}) == {:error, :unknown_table}
    end

    test "writing a struct whose module is not managed returns :unknown_table" do
      assert MultiRepo.write(%{__struct__: NotManaged, name: "x"}) == {:error, :unknown_table}
    end
  end

  describe "reload_seeds/1" do
    test "re-runs the table's seed file" do
      assert MultiRepo.all(Widget) == []

      assert MultiRepo.reload_seeds(Widget) == {:ok, :seed_success}
      assert {:ok, seeded} = MultiRepo.one(Widget, %{name: "seed_widget", color: "green"})
      assert seeded.color == "green"
    end

    test "an undeclared table returns :unknown_table" do
      assert MultiRepo.reload_seeds(NotManaged) == {:error, :unknown_table}
    end
  end

  describe "resilience" do
    test "ETS data survives a repo crash and before_init runs on restart" do
      Process.flag(:trap_exit, true)

      {:ok, _record} = MultiRepo.write(%Widget{name: "survivor", color: "purple"})
      {:ok, _record} = MultiRepo.write(%Gadget{name: "mnesia_survivor", category: "keep"})

      pid = Process.whereis(MultiRepo)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # the ETS table is preserved by the heir
      assert :ets.whereis(Widget) != :undefined
      assert :ets.info(Widget, :owner) == TableHeir.whereis()

      {:ok, _pid} = MultiRepo.start_link()

      # recovered data is intact for both adapters
      assert {:ok, survivor} = MultiRepo.one(Widget, %{name: "survivor", color: "purple"})
      assert survivor.name == "survivor"
      assert {:ok, _gadget} = MultiRepo.one(Gadget, %{name: "mnesia_survivor"})

      # before_init still runs on recovery...
      assert {:ok, _warmed} = MultiRepo.one(Widget, %{name: "warmed", color: "blue"})
      # ...but the seed file is not re-run on a recovered table
      assert MultiRepo.one(Widget, %{name: "seed_widget", color: "green"}) == {:error, :not_found}
    end
  end
end
