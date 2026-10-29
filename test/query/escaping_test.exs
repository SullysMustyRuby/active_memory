defmodule ActiveMemory.Query.EscapingTest do
  # Query values must be compared as values. ETS and Mnesia read `:_` and atoms like
  # `:"$1"` as match syntax and let a map match any map holding its keys, so a value
  # taken from user input must never widen a query beyond the records it names.
  use ExUnit.Case, async: false

  alias Test.Support.Dogs.Dog
  alias Test.Support.Dogs.Store, as: DogStore
  alias Test.Support.People.Person
  alias Test.Support.People.Store, as: PeopleStore
  alias Test.Support.ProcessHelper

  import ActiveMemory.Query

  setup_all do
    ProcessHelper.stop(DogStore)
    ProcessHelper.stop(PeopleStore)
    {:ok, _pid} = DogStore.start_link()
    {:ok, _pid} = PeopleStore.start_link()

    on_exit(fn ->
      ProcessHelper.stop(DogStore)
      ProcessHelper.stop(PeopleStore)

      case :ets.whereis(Dog) do
        :undefined -> :ok
        _table_ref -> :ets.delete(Dog)
      end

      :mnesia.delete_table(Person)
    end)

    :ok
  end

  setup do
    :ok = DogStore.delete_all()
    :ok = PeopleStore.delete_all()

    {:ok, _} = DogStore.write(%Dog{name: "gem", breed: "Lab", nested: %{owner: "erin"}})

    {:ok, _} =
      DogStore.write(%Dog{name: "rex", breed: "Husky", nested: %{owner: "laura", vet: "b"}})

    {:ok, _} =
      PeopleStore.write(%Person{email: "erin@example.com", first: "erin", last: "boeger"})

    {:ok, _} =
      PeopleStore.write(%Person{email: "laura@example.com", first: "laura", last: "roslin"})

    :ok
  end

  describe "ets map queries" do
    test "a wildcard value matches nothing" do
      assert {:error, :not_found} == DogStore.one(%{name: :_})
      assert {:ok, []} == DogStore.select(%{breed: :"$1"})
    end

    test "a map value matches only an equal map" do
      assert {:ok, []} == DogStore.select(%{nested: %{}})
      assert {:ok, []} == DogStore.select(%{nested: %{owner: "laura"}})
      assert {:ok, [%Dog{name: "gem"}]} = DogStore.select(%{nested: %{owner: "erin"}})
    end

    test "withdraw with a wildcard value removes nothing" do
      assert {:error, :not_found} == DogStore.withdraw(%{name: :_})
      assert DogStore.count() == 2
    end

    test "withdraw removes exactly the record holding a map" do
      assert {:ok, %Dog{name: "rex"}} = DogStore.withdraw(%{name: "rex"})
      assert DogStore.count() == 1
    end
  end

  describe "ets match queries" do
    test "an atom value is not read as a field variable" do
      value = :"$2"

      assert {:ok, []} == DogStore.select(match(:breed == value))
    end

    test "a tuple value is compared as a literal" do
      value = {:a, :b, :c}
      {:ok, _} = DogStore.write(%Dog{name: value, breed: "Tuple"})

      assert {:ok, [%Dog{breed: "Tuple"}]} = DogStore.select(match(:name == value))
    end

    test "a map value is compared as a literal" do
      value = %{owner: "erin"}

      assert {:ok, [%Dog{name: "gem"}]} = DogStore.select(match(:nested == value))
    end

    # A match query finds exactly one record, so these isolate the delete step: the
    # withdrawn record's own values must not widen what gets deleted.
    test "withdraw deletes only the record whose key is a map" do
      key = %{id: 1}
      {:ok, _} = DogStore.write(%Dog{name: key, breed: "Map"})
      {:ok, _} = DogStore.write(%Dog{name: %{id: 1, extra: 2}, breed: "Map"})

      assert {:ok, %Dog{name: ^key}} = DogStore.withdraw(match(:name == key))
      assert {:ok, [%Dog{name: %{id: 1, extra: 2}}]} = DogStore.select(%{breed: "Map"})
    end

    test "withdraw deletes only the record whose key is :_" do
      {:ok, _} = DogStore.write(%Dog{name: :_, breed: "Wild"})
      {:ok, _} = DogStore.write(%Dog{name: "other", breed: "Wild"})

      assert {:ok, %Dog{name: :_}} = DogStore.withdraw(match(:name == :_))
      assert {:ok, [%Dog{name: "other"}]} = DogStore.select(%{breed: "Wild"})
    end
  end

  describe "mnesia map queries" do
    test "a wildcard value matches nothing" do
      assert {:error, :not_found} == PeopleStore.one(%{first: :_})
      assert {:ok, []} == PeopleStore.select(%{last: :"$4"})
    end

    test "withdraw with a wildcard value removes nothing" do
      assert {:error, :not_found} == PeopleStore.withdraw(%{first: :_})
      assert PeopleStore.count() == 2
    end

    test "literal values still match on an indexed field" do
      assert {:ok, [%Person{first: "erin"}]} = PeopleStore.select(%{last: "boeger"})
      assert {:ok, %Person{first: "laura"}} = PeopleStore.withdraw(%{last: "roslin"})
    end
  end

  describe "mnesia match queries" do
    test "an atom value is not read as a field variable" do
      value = :"$4"

      assert {:ok, []} == PeopleStore.select(match(:last == value))
      assert {:error, :not_found} == PeopleStore.withdraw(match(:last == value))
    end
  end
end
