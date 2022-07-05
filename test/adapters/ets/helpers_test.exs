defmodule ActiveMemory.Adapters.Ets.HelpersTest do
  use ExUnit.Case

  alias ActiveMemory.Adapters.Ets.Helpers

  describe "build_match_head/1" do
  end

  describe "to_struct/2" do
  end

  describe "to_tuple/1" do
  end

  describe "build_options/1" do
    test "returns a list of valid :ets options" do
      options = [type: :ordered_set, access: :protected, compressed: true]
      assert [:ordered_set, :protected, :compressed] == Helpers.build_options(options)

      options = [
        type: :ordered_set,
        access: :protected,
        read_concurrency: true,
        write_concurrency: true
      ]

      assert [
               :ordered_set,
               :protected,
               {:read_concurrency, true},
               {:write_concurrency, true}
             ] == Helpers.build_options(options)
    end

    test "ignores invalid or malformed options" do
      options = [type: :large, access: :sure, compressed: "yes"]
      assert [:set, :public] == Helpers.build_options(options)
    end

    test "returns defaults when no options" do
      assert [:set, :public] == Helpers.build_options(:defaults)
      assert [:set, :public] == Helpers.build_options([])
    end
  end
end
