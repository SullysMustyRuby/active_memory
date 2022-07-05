defmodule ActiveMemory.Adapter.HelpersTest do
  use ExUnit.Case

  alias ActiveMemory.Adapter.Helpers
  alias Test.Support.Dogs.Dog

  describe "build_match_head/1 for ets" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {:"$1", :"$2", :"$3", :"$4"} ==
               Helpers.build_match_head(query_map, Dog, :ets)
    end
  end

  describe "build_match_head/1 for mnesia" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {Dog, :"$1", :"$2", :"$3", :"$4"} ==
               Helpers.build_match_head(query_map, Dog, :mnesia)
    end
  end

  describe "build_query_map/1" do
    test "returns a list of tuples indexed for simple key attributes" do
      attributes = [:name, :breed, :weight, :fixed?]

      assert [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"] ==
               Helpers.build_query_map(attributes)
    end

    test "returns a list of tuples indexed for complex attributes with defaults" do
      attributes = [:name, :breed, :weight, fixed?: true, nested: %{one: nil, default: true}]

      assert [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4", nested: :"$5"] ==
               Helpers.build_query_map(attributes)
    end
  end

  describe "build_struct_keys/1" do
    test "returns a list of keys for simple attributes" do
      attributes = [:name, :breed, :weight, :fixed?]

      assert [:name, :breed, :weight, :fixed?] ==
               Helpers.build_struct_keys(attributes)
    end

    test "returns a list of keys for complex attributes with defaults" do
      attributes = [:name, :breed, :weight, fixed?: true, nested: %{one: nil, default: true}]

      assert [:name, :breed, :weight, :fixed?, :nested] ==
               Helpers.build_struct_keys(attributes)
    end
  end
end
