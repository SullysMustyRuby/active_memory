defmodule ActiveMemory.StoreTest do
  use ExUnit.Case, async: false

  alias Test.Support.Dogs.Dog
  alias Test.Support.Dogs.Store, as: DogStore
  alias Test.Support.People.Store, as: PeopleStore
  alias Test.Support.People.Person

  describe "init with options" do
    test "with a valid seed file populates the store" do
      {:ok, pid} = PeopleStore.start_link()

      people = PeopleStore.all()
      assert length(people) == 10

      :mnesia.delete_table(Person)
      Process.exit(pid, :kill)
    end

    test "with a table error" do
      assert Dog == :ets.new(Dog, [:named_table, :public, read_concurrency: true])

      Process.flag(:trap_exit, true)

      assert DogStore.start_link() == {:error, :create_table_failed}

      :ets.delete(Dog)
    end

    test "with before_init method" do
      {:ok, pid} = DogStore.start_link()
      {:ok, dog} = DogStore.one(%{name: "Blue"})

      assert dog.name == "Blue"

      :ets.delete(Dog)
      Process.exit(pid, :kill)
    end

    test "initial state with no method returns table name and started_at" do
      {:ok, pid} = PeopleStore.start_link()

      state = PeopleStore.state()
      assert state.table_name == Person
      assert DateTime.diff(DateTime.utc_now(), state.started_at) < 10

      :mnesia.delete_table(Person)
      Process.exit(pid, :kill)
    end

    test "initial state with a method returns method state" do
      {:ok, pid} = DogStore.start_link()

      state = DogStore.state()
      assert state.key == "value"
      assert state.next == "next_value"
      assert DateTime.diff(DateTime.utc_now(), state.now) < 10

      :ets.delete(Dog)
      Process.exit(pid, :kill)
    end
  end
end
