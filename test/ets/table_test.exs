defmodule ActiveMemory.Ets.TableTest do
  use ExUnit.Case

  alias Test.Support.Dogs.Dog

  setup do
    attributes = %{
      breed: "Shaggy Black Lab",
      weight: 30,
      fixed?: false,
      name: "gem"
    }

    {:ok, %{attributes: attributes}}
  end

  describe "to_tuple" do
    test "returns a tuple with the attributes in correct order", %{attributes: attributes} do
      struct = struct(Dog, attributes)

      assert {"gem", "Shaggy Black Lab", 30, false} == Dog.to_tuple(struct)
    end
  end

  describe "to_struct" do
    test "returns a struct with the attributes in correct order" do
      tuple = {"gem", "Shaggy Black Lab", 30, false}
      dog = Dog.to_struct(tuple)

      assert dog.__struct__ == Dog
      assert dog.name == "gem"
      assert dog.breed == "Shaggy Black Lab"
      assert dog.weight == 30
      refute dog.fixed?
    end
  end
end
