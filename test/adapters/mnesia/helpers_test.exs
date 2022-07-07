defmodule ActiveMemory.Adapters.Mnesia.HelpersTest do
  use ExUnit.Case

  alias ActiveMemory.Adapters.Mnesia.Helpers
  alias Test.Support.People.Person

  describe "build_match_head/1" do
    test "returns a tuple formatted for simple key list" do
      query_map = [name: :"$1", breed: :"$2", weight: :"$3", fixed?: :"$4"]

      assert {Dog, :"$1", :"$2", :"$3", :"$4"} ==
               Helpers.build_match_head(query_map, Dog)
    end
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

  describe "to_struct/2" do
    test "returns a valid struct for the module provided" do
      person = {Person, "caprica@galactica.com", "caprica", "boeger", "blonde", 31, true}

      assert Helpers.to_struct(person, Person) == %Person{
               email: "caprica@galactica.com",
               first: "caprica",
               last: "boeger",
               hair_color: "blonde",
               age: 31,
               cylon?: true
             }
    end
  end

  describe "to_tuple/1" do
    person = %Person{
      email: "caprica@galactica.com",
      first: "caprica",
      last: "boeger",
      hair_color: "blonde",
      age: 31,
      cylon?: true
    }

    assert Helpers.to_tuple(person) ==
             {Person, "caprica@galactica.com", "caprica", "boeger", "blonde", 31, true}
  end
end
