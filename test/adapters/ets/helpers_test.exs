defmodule ActiveMemory.Adapters.Ets.HelpersTest do
  use ExUnit.Case

  alias ActiveMemory.Adapters.Ets.Helpers
  alias Test.Support.Dogs.Dog

  describe "build_match_head/1" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {:"$1", :"$2", :"$3", :"$4"} ==
               Helpers.build_match_head(query_map)
    end
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

    test "accepts false for the boolean options" do
      options = [compressed: false, read_concurrency: false, write_concurrency: false]

      assert [:set, :public, {:read_concurrency, false}, {:write_concurrency, false}] ==
               Helpers.build_options(options)
    end

    test "raises on an unknown option" do
      assert_raise ArgumentError, ~r/unknown ETS table option :size/, fn ->
        Helpers.build_options(size: 10)
      end
    end

    test "raises on an invalid value" do
      for option <- [type: :large, access: :sure, compressed: "yes", write_concurrency: :maybe] do
        assert_raise ArgumentError, ~r/invalid value .* for the ETS table option/, fn ->
          Helpers.build_options([option])
        end
      end
    end

    test "raises on an option ActiveMemory sets itself" do
      for option <- [keypos: 2, named_table: true, heir: :none] do
        assert_raise ArgumentError, ~r/is set by ActiveMemory/, fn ->
          Helpers.build_options([option])
        end
      end
    end

    test "raises when the options are not a keyword list" do
      for options <- [[:compressed], %{type: :set}, :none] do
        assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
          Helpers.build_options(options)
        end
      end
    end

    test "returns defaults when no options" do
      assert [:set, :public] == Helpers.build_options(:defaults)
      assert [:set, :public] == Helpers.build_options([])
    end
  end

  describe "to_struct/2" do
    test "returns a valid struct for the module provided" do
      dog =
        {"gem", "Shaggy Black Lab", 30, ~U[2022-07-07 19:47:50.978684Z], false, %{toy: "frizbee"}}

      assert Helpers.to_struct(dog, Dog) == %Dog{
               dob: ~U[2022-07-07 19:47:50.978684Z],
               name: "gem",
               breed: "Shaggy Black Lab",
               nested: %{toy: "frizbee"},
               weight: 30,
               fixed?: false
             }
    end
  end

  describe "to_tuple/1" do
    dog = %Dog{
      dob: ~U[2022-07-07 19:47:50.978684Z],
      name: "gem",
      breed: "Shaggy Black Lab",
      nested: %{toy: "frizbee"},
      weight: 30,
      fixed?: false
    }

    assert Helpers.to_tuple(dog) ==
             {"gem", "Shaggy Black Lab", 30, ~U[2022-07-07 19:47:50.978684Z], false,
              %{toy: "frizbee"}}
  end
end
