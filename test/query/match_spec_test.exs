defmodule ActiveMemory.Query.MatchSpecTest do
  use ExUnit.Case

  alias ActiveMemory.Query.MatchSpec
  alias Test.Support.Dogs.Dog

  import ActiveMemory.Query

  describe "build/2" do
    test "returns a properly formatted match_spec" do
      query = match(:breed == "PitBull" and :weight > 40 and :fixed? == false)

      query_map = :erlang.apply(Dog, :__attributes__, [:query_map])
      match_head = :erlang.apply(Dog, :__attributes__, [:match_head])

      [{match_head, query, result}] = MatchSpec.build(query, query_map, match_head)

      assert match_head == {:"$1", :"$2", :"$3", :"$4", :"$5", :"$6"}

      assert query == [
               {:and, {:and, {:==, :"$2", "PitBull"}, {:>, :"$3", 40}}, {:==, :"$5", false}}
             ]

      assert result == [:"$_"]
    end

    test "returns variables interpolated" do
      breed = "PitBull"
      weight = 40
      fixed = false
      query = match(:breed == breed and :weight > weight and :fixed? == fixed)

      query_map = :erlang.apply(Dog, :__attributes__, [:query_map])
      match_head = :erlang.apply(Dog, :__attributes__, [:match_head])

      [{_match_head, query, _result}] = MatchSpec.build(query, query_map, match_head)

      assert query == [
               {:and, {:and, {:==, :"$2", "PitBull"}, {:>, :"$3", 40}}, {:==, :"$5", false}}
             ]
    end
  end
end
