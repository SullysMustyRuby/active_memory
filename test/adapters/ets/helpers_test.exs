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

    test "ignores invalid or malformed options" do
      options = [type: :large, access: :sure, compressed: "yes"]
      assert [:set, :public] == Helpers.build_options(options)
    end

    test "returns defaults when no options" do
      assert [:set, :public] == Helpers.build_options(:defaults)
      assert [:set, :public] == Helpers.build_options([])
    end
  end

  describe "to_struct/2" do
    test "returns a valid struct for the module provided" do
      dog =
        {"some-uuid", "gem", "Shaggy Black Lab", 30, ~U[2022-07-07 19:47:50.978684Z], false,
         %{toy: "frizbee"}}

      assert Helpers.to_struct(dog, Dog) == %Dog{
               uuid: "some-uuid",
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
      uuid: "some-uuid",
      dob: ~U[2022-07-07 19:47:50.978684Z],
      name: "gem",
      breed: "Shaggy Black Lab",
      nested: %{toy: "frizbee"},
      weight: 30,
      fixed?: false
    }

    assert Helpers.to_tuple(dog) ==
             {"some-uuid", "gem", "Shaggy Black Lab", 30, ~U[2022-07-07 19:47:50.978684Z], false,
              %{toy: "frizbee"}}
  end
end
