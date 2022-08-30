defmodule ActiveMemory.Table.AttributesTest do
  use ExUnit.Case, async: false

  alias Test.Support.Whales.Whale
  alias Test.Support.Dogs.Dog

  describe "attributes" do
    test "adds fields to list" do
      res = %{
        adapter: Whale.__attributes__(:adapter),
        attributes: Whale.__attributes__(:query_fields),
        match_head: Whale.__attributes__(:match_head),
        query_map: Whale.__attributes__(:query_map),
        table_options: Whale.__attributes__(:table_options)
      }

      # match_head = Whale.__attributes__(:match_head)
      require IEx
      IEx.pry()
      # primary_key = Whale.__attributes__(:primary_key)
      # fields = Whale.__attributes__(:fields)
      # m = Whale.__meta__()
    end
  end
end
