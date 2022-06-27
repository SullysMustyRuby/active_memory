defmodule QueryTest do
  use ExUnit.Case

  import ActiveMemory.Query

  describe "match" do
    test "turns the syntax into proper match" do
      assert {:or, {:==, :name, "erin"}, {:==, :name, "tiberious"}} ==
               match(:name == "erin" or :name == "tiberious")

      assert {:or, {:and, {:==, :name, "erin"}, {:==, :name, "tiberious"}}, {:<, :age, 35}} ==
               match((:name == "erin" and :name == "tiberious") or :age < 35)
    end
  end
end

# :ets.fun2ms(fn {name, age, type} when name == "erin" and age > 30 or type == "hello" -> {name, age} end)

# [
#   {{:"$1", :"$2", :"$3"},
#    [
#      {:orelse, {:andalso, {:==, :"$1", "erin"}, {:>, :"$2", 30}},
#       {:==, :"$3", "hello"}}
#    ], [{{:"$1", :"$2"}}]}
# ]
