defmodule ActiveMemory.Adapter.HelpersTest do
  use ExUnit.Case

  alias ActiveMemory.Adapter.Helpers

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
end
