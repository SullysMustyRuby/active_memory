defmodule SelectTest do
  use ExUnit.Case

  import ActiveMemory.Select

  describe "select" do
    test "turns the syntax into proper select" do
      assert {:or, {:==, :name, "erin"}, {:==, :name, "tiberious"}} ==
               select(:name == "erin" or :name == "tiberious")

      assert {:or, {:and, {:==, :name, "erin"}, {:==, :name, "tiberious"}}, {:<, :age, 35}} ==
               select((:name == "erin" and :name == "tiberious") or :age < 35)
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
