defmodule ActiveMemory.Query.MatchSpecTest do
  use ExUnit.Case

  alias ActiveMemory.Query.MatchSpec
  alias Test.Support.Dogs.Dog

  import ActiveMemory.Query

  describe "build/2" do
    test "returns a properly formatted match_spec" do
      query = match(:breed == "PitBull" and :weight > 40 and :fixed? == false)

      query_map = :erlang.apply(Dog, :__meta__, []) |> Map.get(:query_map)
      match_head = :erlang.apply(Dog, :__meta__, []) |> Map.get(:ets_match_head)

      [{match_head, query, result}] = MatchSpec.build(query, query_map, match_head)

      assert match_head == {:"$1", :"$2", :"$3", :"$4", :"$5"}

      assert query == [
               {:and, {:and, {:==, :"$2", "PitBull"}, {:>, :"$3", 40}}, {:==, :"$4", false}}
             ]

      assert result == [:"$_"]
    end
  end
end
