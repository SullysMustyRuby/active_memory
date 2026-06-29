defmodule ActiveMemory.TableHeirTest do
  use ExUnit.Case, async: false
  doctest ActiveMemory.TableHeir

  alias ActiveMemory.TableHeir

  defmodule Widget do
    use ActiveMemory.Table, type: :ets

    attributes do
      field(:name)
      field(:color)
    end
  end

  defmodule WidgetStore do
    use ActiveMemory.Store, table: ActiveMemory.TableHeirTest.Widget
  end

  describe "application start" do
    test "the table heir is started and registered" do
      assert is_pid(TableHeir.whereis())
    end
  end

  describe "ETS table recovery" do
    setup do
      on_exit(fn ->
        case :ets.whereis(Widget) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Widget)
        end
      end)

      :ok
    end

    test "data survives a store crash and is reclaimed on restart" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = WidgetStore.start_link()
      {:ok, _record} = WidgetStore.write(%Widget{name: "gizmo", color: "blue"})
      assert {:ok, %{name: "gizmo"}} = WidgetStore.one(%{name: "gizmo", color: "blue"})

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # the heir preserved the table rather than letting ETS destroy it
      assert :ets.whereis(Widget) != :undefined
      assert :ets.info(Widget, :owner) == TableHeir.whereis()

      {:ok, _pid} = WidgetStore.start_link()
      assert {:ok, recovered} = WidgetStore.one(%{name: "gizmo", color: "blue"})
      assert recovered.name == "gizmo"
      assert recovered.color == "blue"

      Process.exit(Process.whereis(WidgetStore), :kill)
    end
  end
end
