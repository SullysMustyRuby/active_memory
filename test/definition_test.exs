defmodule ActiveMemory.DefinitionTest do
  use ExUnit.Case

  alias ActiveMemory.Definition
  alias Test.Support.Dogs.Dog

  describe "build_ets_match_head/1" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {:"$1", :"$2", :"$3", :"$4"} ==
               Definition.build_ets_match_head(query_map, Dog)
    end
  end

  describe "build_mnesia_match_head/1" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {Dog, :"$1", :"$2", :"$3", :"$4"} ==
               Definition.build_mnesia_match_head(query_map, Dog)
    end
  end

  describe "build_query_map/1" do
    test "returns a list of tuples indexed for simple key attributes" do
      attributes = [:name, :breed, :weight, :fixed?]

      assert [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"] ==
               Definition.build_query_map(attributes)
    end

    test "returns a list of tuples indexed for complex attributes with defaults" do
      attributes = [:name, :breed, :weight, fixed?: true, nested: %{one: nil, default: true}]

      assert [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4", nested: :"$5"] ==
               Definition.build_query_map(attributes)
    end
  end

  describe "build_struct_keys/1" do
    test "returns a list of keys for simple attributes" do
      attributes = [:name, :breed, :weight, :fixed?]

      assert [:name, :breed, :weight, :fixed?] ==
               Definition.build_struct_keys(attributes)
    end

    test "returns a list of keys for complex attributes with defaults" do
      attributes = [:name, :breed, :weight, fixed?: true, nested: %{one: nil, default: true}]

      assert [:name, :breed, :weight, :fixed?, :nested] ==
               Definition.build_struct_keys(attributes)
    end
  end
end
