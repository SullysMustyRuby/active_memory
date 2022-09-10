defmodule ActiveMemory.TableTest do
  use ExUnit.Case, async: false

  alias Test.Support.Whales.Whale
  alias Test.Support.People.Person

  describe "__attributes__" do
    test "defines the attributes" do
      assert Whale.__attributes__(:query_fields) == [
               :email,
               :first,
               :last,
               :hair_color,
               :age
             ]

      assert Whale.__attributes__(:query_map) == [
               email: :"$1",
               first: :"$2",
               last: :"$3",
               hair_color: :"$4",
               age: :"$5"
             ]

      assert Whale.__attributes__(:adapter) == ActiveMemory.Adapters.Mnesia
      assert Whale.__attributes__(:table_options) == [index: [:first, :last, :email]]

      assert Whale.__attributes__(:match_head) ==
               {Test.Support.Whales.Whale, :"$1", :"$2", :"$3", :"$4", :"$5"}

      refute Whale.__attributes__(:auto_generate_uuid)

      assert Person.__attributes__(:auto_generate_uuid)
    end
  end
end
