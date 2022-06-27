defmodule ActiveMemory.MatchSpecTest do
  use ExUnit.Case

  alias ActiveMemory.MatchSpec
  alias Test.Support.Dogs.Dog

  import ActiveMemory.Query

  describe "build/2" do
    test "returns a properly formatted match_spec" do
      query = match(:breed == "PitBull" and :weight > 40 and :fixed? == false)
      [{match_head, query, result}] = MatchSpec.build(query, Dog)

      assert match_head == {:"$1", :"$2", :"$3", :"$4"}

      assert query == [
               {:and, {:and, {:==, :"$2", "PitBull"}, {:>, :"$3", 40}}, {:==, :"$4", false}}
             ]

      assert result == [:"$_"]
    end
  end
end
