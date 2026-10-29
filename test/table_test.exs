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

      assert Whale.__attributes__(:table_options) == [
               {:index, [:first, :last]},
               {:ram_copies, [:"app_instance1@127.0.0.1"]}
             ]

      assert Whale.__attributes__(:match_head) ==
               {Test.Support.Whales.Whale, :"$1", :"$2", :"$3", :"$4", :"$5"}

      refute Whale.__attributes__(:auto_generate_uuid)

      assert Person.__attributes__(:auto_generate_uuid)
    end
  end

  describe "use ActiveMemory.Table with options" do
    test "an invalid option fails to compile the table" do
      source = """
      defmodule ActiveMemory.TableTest.MisconfiguredTable do
        use ActiveMemory.Table, type: :ets, options: [type: :protected]

        attributes do
          field(:name)
        end
      end
      """

      assert_raise ArgumentError,
                   ~r/invalid value :protected for the ETS table option :type/,
                   fn ->
                     Code.compile_string(source)
                   end
    end
  end
end
