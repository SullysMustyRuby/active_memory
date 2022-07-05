defmodule ActiveMemory.Adapters.Mnesia.HelpersTest do
  use ExUnit.Case

  alias ActiveMemory.Adapters.Mnesia.Helpers

  describe "build_match_head/1" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {Dog, :"$1", :"$2", :"$3", :"$4"} ==
               Helpers.build_match_head(query_map, Dog)
    end
  end

  describe "to_struct/2" do
  end

  describe "to_tuple/1" do
  end

  describe "build_options/1" do
    test "returns a valid Mnesia keyword list of options" do
      options = [
        access_mode: :read_only,
        disc_copies: [node()],
        load_order: 3,
        majority: true,
        index: [:name, :uuid, :email],
        type: :bag
      ]

      assert Helpers.build_options(options) == options
    end

    test "ignores invalid options" do
      options = [load_order: -1, majority: "yup", size: "huh?"]

      assert Helpers.build_options(options) == []
    end
  end
end
