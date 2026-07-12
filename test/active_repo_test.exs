defmodule ActiveMemory.ActiveRepoTest do
  use ExUnit.Case, async: false

  import ActiveMemory.Query

  alias ActiveMemory.TableHeir
  alias Test.Support.Multi.Gadget
  alias Test.Support.Multi.Gizmo
  alias Test.Support.Multi.InitRepo
  alias Test.Support.Multi.Repo, as: MultiRepo
  alias Test.Support.Multi.Widget
  alias Test.Support.ProcessHelper

  setup_all do
    ProcessHelper.stop(MultiRepo)
    {:ok, pid} = MultiRepo.start_link()

    on_exit(fn ->
      ProcessHelper.stop(MultiRepo)

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

  describe "init with options" do
    setup do
      reset = fn ->
        ProcessHelper.stop(InitRepo)

        case :ets.whereis(Gizmo) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Gizmo)
        end
      end

      reset.()
      on_exit(reset)

      :ok
    end

    test "with a custom initial_state option sets the state" do
      {:ok, _pid} = InitRepo.start_link()

      assert InitRepo.state() == %{key: "primary", fallback: "secondary"}
    end

    test "with a seed_file populates the table on first start" do
      {:ok, _pid} = InitRepo.start_link()

      assert {:ok, gizmo} = InitRepo.one(Gizmo, %{name: "seed_gizmo"})
      assert gizmo.name == "seed_gizmo"
    end

    test "with a before_init method runs it on first start" do
      {:ok, _pid} = InitRepo.start_link()

      assert {:ok, gizmo} = InitRepo.one(Gizmo, %{name: "warmed"})
      assert gizmo.name == "warmed"
    end

    test "with a table that cannot be created returns an error" do
      Process.flag(:trap_exit, true)

      assert Gizmo == :ets.new(Gizmo, [:named_table, :public, read_concurrency: true])

      assert InitRepo.start_link() == {:error, :create_table_failed}

      :ets.delete(Gizmo)
    end
  end

  describe "state/0" do
    test "with no initial_state option lists the managed tables" do
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

  describe "one/2" do
    test "returns a record matching a map query" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "match", color: "blue"})

      assert {:ok, widget} = MultiRepo.one(Widget, %{name: "match", color: "blue"})
      assert widget.name == "match"
    end

    test "returns a record matching a match/1 query" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "matcher", color: "green"})

      query = match(:name == "matcher" and :color == "green")
      assert {:ok, widget} = MultiRepo.one(Widget, query)
      assert widget.color == "green"
    end

    test "returns :not_found when nothing matches" do
      assert MultiRepo.one(Widget, %{name: "nope", color: "none"}) == {:error, :not_found}
    end

    test "returns :more_than_one_result when several match" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "a", color: "blue"})
      {:ok, _record} = MultiRepo.write(%Widget{name: "b", color: "blue"})

      assert MultiRepo.one(Widget, %{color: "blue"}) == {:error, :more_than_one_result}
    end

    test "returns :query_schema_mismatch for unknown keys" do
      assert MultiRepo.one(Widget, %{not_a_field: "x"}) == {:error, :query_schema_mismatch}
    end
  end

  describe "select/2" do
    test "returns all records matching a map query" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "a", color: "blue"})
      {:ok, _record} = MultiRepo.write(%Widget{name: "b", color: "blue"})

      assert {:ok, widgets} = MultiRepo.select(Widget, %{color: "blue"})
      assert length(widgets) == 2
    end

    test "returns all records matching a match/1 query" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "a", color: "blue"})
      {:ok, _record} = MultiRepo.write(%Widget{name: "b", color: "red"})

      assert {:ok, widgets} = MultiRepo.select(Widget, match(:color == "blue"))
      assert length(widgets) == 1
    end

    test "returns an empty list when nothing matches" do
      assert MultiRepo.select(Widget, %{color: "none"}) == {:ok, []}
    end

    test "returns :bad_select_query for an invalid query" do
      assert MultiRepo.select(Widget, "not a query") == {:error, :bad_select_query}
    end
  end

  describe "withdraw/2" do
    test "fetches and deletes a record" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "gone", color: "blue"})

      assert {:ok, widget} = MultiRepo.withdraw(Widget, %{name: "gone", color: "blue"})
      assert widget.name == "gone"
      assert MultiRepo.one(Widget, %{name: "gone", color: "blue"}) == {:error, :not_found}
    end

    test "returns :not_found when nothing matches" do
      assert MultiRepo.withdraw(Widget, %{name: "missing", color: "none"}) ==
               {:error, :not_found}
    end
  end

  describe "delete/1 and delete_all/1" do
    test "delete removes a record, inferring the table from the struct" do
      {:ok, widget} = MultiRepo.write(%Widget{name: "x", color: "blue"})

      assert :ok = MultiRepo.delete(widget)
      assert MultiRepo.all(Widget) == []
    end

    test "delete_all clears a single table without touching the others" do
      {:ok, _record} = MultiRepo.write(%Widget{name: "x", color: "blue"})
      {:ok, _record} = MultiRepo.write(%Gadget{name: "y", category: "z"})

      assert MultiRepo.delete_all(Widget) == :ok

      assert MultiRepo.all(Widget) == []
      assert length(MultiRepo.all(Gadget)) == 1
    end

    test "delete_all returns :ok for both ets and mnesia tables" do
      assert MultiRepo.delete_all(Widget) == :ok
      assert MultiRepo.delete_all(Gadget) == :ok
    end
  end

  describe "unknown tables" do
    test "reads and deletes on an undeclared table return :unknown_table" do
      assert MultiRepo.all(NotManaged) == {:error, :unknown_table}
      assert MultiRepo.one(NotManaged, %{}) == {:error, :unknown_table}
      assert MultiRepo.select(NotManaged, %{}) == {:error, :unknown_table}
      assert MultiRepo.withdraw(NotManaged, %{}) == {:error, :unknown_table}
      assert MultiRepo.delete_all(NotManaged) == {:error, :unknown_table}
    end

    test "writing a struct whose module is not managed returns :unknown_table" do
      assert MultiRepo.write(%{__struct__: NotManaged, name: "x"}) == {:error, :unknown_table}
    end

    test "writing a non-struct map returns :unknown_table" do
      assert MultiRepo.write(%{name: "x"}) == {:error, :unknown_table}
    end

    test "deleting a struct whose module is not managed returns :unknown_table" do
      assert MultiRepo.delete(%{__struct__: NotManaged, name: "x"}) == {:error, :unknown_table}
    end
  end

  describe "reload_seeds/1" do
    test "re-runs the table's seed file" do
      assert MultiRepo.all(Widget) == []

      assert MultiRepo.reload_seeds(Widget) == {:ok, :seed_success}
      assert {:ok, seeded} = MultiRepo.one(Widget, %{name: "seed_widget", color: "green"})
      assert seeded.color == "green"
    end

    test "is a no-op for a table configured without a seed_file" do
      assert MultiRepo.reload_seeds(Gadget) == {:ok, :seed_success}
      assert MultiRepo.all(Gadget) == []
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
