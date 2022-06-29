defmodule ActiveMemory.MatchGuardsTest do
  use ExUnit.Case

  alias ActiveMemory.Query.MatchGuards

  defmodule Tester do
    use ActiveMemory.Table, attributes: [:email, :first, :last, :hair_color, :shoe_size]
  end

  defmodule Tester.Store do
    use ActiveMemory.Store, table: Tester
  end

  setup_all do
    {:ok, pid} = Tester.Store.start_link()

    on_exit(fn -> :mnesia.delete_table(Tester) end)

    {:ok, %{pid: pid}}
  end

  describe "build_match_query/2" do
    test "returns the query strings in the correct positions" do
      query_map = %{last: "boeger", shoe_size: "13"}

      assert {:ok, {:_, :_, "boeger", :_, "13"}} == MatchGuards.build(Tester, query_map)
    end

    test "returns error for keys that do not match" do
      query_map = %{ears: "two", nose: "kinda big"}

      assert {:error, :query_schema_mismatch} == MatchGuards.build(Tester, query_map)
    end
  end
end
