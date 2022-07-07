defmodule ActiveMemory.Query.MatchGuardsTest do
  use ExUnit.Case

  alias ActiveMemory.Query.MatchGuards

  alias Test.Support.People.{Person, Store}

  setup_all do
    {:ok, pid} = Store.start_link()

    on_exit(fn -> :mnesia.delete_table(Person) end)
    on_exit(fn -> Process.exit(pid, :kill) end)

    {:ok, %{pid: pid}}
  end

  describe "build_match_query/2" do
    test "returns the query strings in the correct positions" do
      query_map = %{last: "boeger", age: 35}

      assert {:ok, {:_, :_, "boeger", :_, 35, :_}} == MatchGuards.build(Person, query_map)
    end

    test "returns error for keys that do not match" do
      query_map = %{ears: "two", nose: "kinda big"}

      assert {:error, :query_schema_mismatch} == MatchGuards.build(Person, query_map)
    end

    test "returns query strings when variables are used" do
      last = "boeger"
      age = 35
      query_map = %{last: last, age: age}

      assert {:ok, {:_, :_, "boeger", :_, 35, :_}} == MatchGuards.build(Person, query_map)
    end
  end
end
