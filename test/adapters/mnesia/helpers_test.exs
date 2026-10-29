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

    test "passes through the options set only at table creation" do
      options = [
        local_content: true,
        storage_properties: [ets: [read_concurrency: true]],
        user_properties: [{:owner, "erin"}]
      ]

      assert Helpers.build_options(options) == options
    end

    test "raises on an unknown option" do
      assert_raise ArgumentError, ~r/unknown Mnesia table option :size/, fn ->
        Helpers.build_options(size: "huh?")
      end
    end

    test "raises on an invalid value" do
      for option <- [
            load_order: -1,
            majority: "yup",
            type: :duplicate_bag,
            disc_copies: node(),
            local_content: "yes",
            user_properties: [:owner]
          ] do
        assert_raise ArgumentError, ~r/invalid value .* for the Mnesia table option/, fn ->
          Helpers.build_options([option])
        end
      end
    end

    test "raises on an option ActiveMemory sets itself" do
      for option <- [attributes: [:a], record_name: :other] do
        assert_raise ArgumentError, ~r/is set by ActiveMemory/, fn ->
          Helpers.build_options([option])
        end
      end
    end

    test "raises when the options are not a keyword list" do
      for options <- [[:index], %{type: :set}, :none] do
        assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
          Helpers.build_options(options)
        end
      end
    end
  end

  describe "to_struct/2" do
    test "returns a valid struct for the module provided" do
      person =
        {Person, "some-uuid", "caprica@galactica.com", "caprica", "boeger", "blonde", 31, true}

      assert Helpers.to_struct(person, Person) == %Person{
               uuid: "some-uuid",
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
      uuid: "some-uuid",
      email: "caprica@galactica.com",
      first: "caprica",
      last: "boeger",
      hair_color: "blonde",
      age: 31,
      cylon?: true
    }

    assert Helpers.to_tuple(person) ==
             {Person, "some-uuid", "caprica@galactica.com", "caprica", "boeger", "blonde", 31,
              true}
  end
end
