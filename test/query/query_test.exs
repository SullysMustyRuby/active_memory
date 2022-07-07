defmodule ActiveMemory.QueryTest do
  use ExUnit.Case

  import ActiveMemory.Query

  describe "match" do
    test "turns the syntax into proper match" do
      assert {:or, {:==, :name, "erin"}, {:==, :name, "tiberious"}} ==
               match(:name == "erin" or :name == "tiberious")

      assert {:or, {:and, {:==, :name, "erin"}, {:==, :name, "tiberious"}}, {:<, :age, 35}} ==
               match((:name == "erin" and :name == "tiberious") or :age < 35)
    end

    test "resolves variables in the match" do
      now = DateTime.utc_now()
      assert match(:date == now) == {:==, :date, now}
    end
  end
end
