defmodule ActiveMemory.Ets.TableTest do
  use ExUnit.Case

  alias Test.Support.Dogs.Dog

  setup do
    attributes = %{
      breed: "Shaggy Black Lab",
      weight: "30",
      fixed?: false,
      name: "gem"
    }

    {:ok, %{attributes: attributes}}
  end

  describe "new" do
    test "returns a struct with the attributes assigned", %{attributes: attributes} do
      struct = Dog.new(attributes)
      assert struct.__struct__ == Dog
      assert struct.breed == "Shaggy Black Lab"
    end
  end

  describe "to_tuple" do
    test "returns a tuple with the attributes in correct order", %{attributes: attributes} do
      struct = Dog.new(attributes)

      tuple_dog = Dog.to_tuple(struct)
      assert is_tuple(tuple_dog)
    end
  end

  describe "to_struct" do
    test "returns a struct with the attributes in correct order", %{attributes: attributes} do
      struct = Dog.new(attributes)

      return_struct = struct |> Dog.to_tuple() |> Dog.to_struct()
      assert return_struct == struct
    end
  end
end
