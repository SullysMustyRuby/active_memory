defmodule ActiveMemory.Table.AttributesTest do
  use ExUnit.Case, async: false

  alias Test.Support.Whales.Whale
  # alias Test.Support.Dogs.Dog

  describe "attributes" do
    test "adds fields to list" do
      res = Whale.schema()
      require IEx
      IEx.pry()
    end
  end
end
