defmodule ActiveMemory.HandleInfoOrderingTest do
  # Regression: the `use ActiveMemory.Store` catch-all handle_info used to be
  # injected above the using module's own handle_info clauses, so custom
  # messages (timer ticks, monitors) were silently swallowed and the clauses
  # were dead code. The catch-all now lands via @before_compile, after them.
  use ExUnit.Case

  defmodule PingTable do
    use ActiveMemory.Table, type: :ets

    attributes do
      field(:name)
    end
  end

  defmodule PingStore do
    use ActiveMemory.Store, table: PingTable

    def handle_info({:ping, from}, state) do
      send(from, :pong)
      {:noreply, state}
    end
  end

  describe "user-defined handle_info clauses" do
    test "receive their messages instead of being swallowed by the catch-all" do
      pid = start_supervised!(PingStore)

      send(pid, {:ping, self()})

      assert_receive :pong, 1_000
    end

    test "unknown messages still fall through to the library catch-all" do
      pid = start_supervised!(PingStore)

      send(pid, :message_no_clause_handles)

      # The store must survive the unknown message and stay responsive.
      assert %{} = PingStore.state()
      assert Process.alive?(pid)
    end
  end
end
