defmodule QueryTest do
  use ExUnit.Case

  import MnesiaCompanion.Query

  describe "where" do
    test "turns the syntax into proper select" do
      query = where(:name == "erin" or :name == "tiberious")
      require IEx
      IEx.pry()
    end
  end
end
