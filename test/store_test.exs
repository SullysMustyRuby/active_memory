defmodule ActiveMemory.StoreTest do
  use ExUnit.Case, async: false

  alias Test.Support.Dogs.Dog
  alias Test.Support.Dogs.Store, as: DogStore
  alias Test.Support.People.Person
  alias Test.Support.People.Store, as: PeopleStore
  alias Test.Support.ProcessHelper

  defmodule IgnoringTable do
    use ActiveMemory.Table, type: :ets

    attributes do
      field(:name)
    end
  end

  defmodule IgnoringStore do
    use ActiveMemory.Store,
      table: ActiveMemory.StoreTest.IgnoringTable,
      initial_state: {:ignore_state, []}

    def ignore_state, do: :ignore
  end

  defmodule UntaggedTable do
    use ActiveMemory.Table, type: :ets

    attributes do
      field(:name)
    end
  end

  defmodule UntaggedStore do
    use ActiveMemory.Store,
      table: ActiveMemory.StoreTest.UntaggedTable,
      initial_state: {:untagged_state, []}

    def untagged_state, do: %{untagged: true}
  end

  defmodule FailingInitTable do
    use ActiveMemory.Table, type: :ets

    attributes do
      field(:name)
    end
  end

  defmodule FailingInitStore do
    use ActiveMemory.Store,
      table: ActiveMemory.StoreTest.FailingInitTable,
      before_init: [{:fail, []}, {:after_fail, []}]

    def fail, do: {:error, :no_source}

    def after_fail, do: send(:active_memory_store_test, :after_fail_ran)
  end

  # The stores are named GenServers; make sure none are lingering from a prior test
  # (or a prior module) before a test starts a fresh one, otherwise `start_link`
  # races with the previous instance's shutdown and returns `{:already_started, _}`.
  setup do
    ProcessHelper.stop(DogStore)
    ProcessHelper.stop(PeopleStore)

    :ok
  end

  describe "init with options" do
    test "with a valid seed file populates the store" do
      {:ok, pid} = PeopleStore.start_link()

      people = PeopleStore.all()
      assert length(people) == 10

      :mnesia.delete_table(Person)
      Process.exit(pid, :kill)
    end

    test "with no initial_state option sets the default state" do
      {:ok, pid} = PeopleStore.start_link()

      assert %{started_at: %DateTime{}, table_name: Person} = PeopleStore.state()

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

    test "with initial_state option sets the custom state" do
      {:ok, pid} = DogStore.start_link()

      assert %{key: "arg1", next: "arg2", now: %DateTime{}} = DogStore.state()

      :ets.delete(Dog)
      Process.exit(pid, :kill)
    end

    test "with an initial_state that does not return {:ok, state}" do
      Process.flag(:trap_exit, true)
      on_exit(fn -> delete_tables([IgnoringTable, UntaggedTable]) end)

      assert {:error, {:invalid_initial_state, :ignore}} = IgnoringStore.start_link()
      assert {:error, {:invalid_initial_state, %{untagged: true}}} = UntaggedStore.start_link()
    end

    test "with a before_init method that returns an error" do
      Process.flag(:trap_exit, true)
      Process.register(self(), :active_memory_store_test)
      on_exit(fn -> delete_tables([FailingInitTable]) end)

      assert {:error, {:before_init, :fail, :no_source}} = FailingInitStore.start_link()
      refute_received :after_fail_ran
    end
  end

  describe "reload_seeds/0" do
    test "repopulates the store from the seed file" do
      {:ok, pid} = PeopleStore.start_link()

      assert PeopleStore.delete_all() == :ok
      assert PeopleStore.all() == []

      assert PeopleStore.reload_seeds() == {:ok, :seed_success}
      assert length(PeopleStore.all()) == 10

      :mnesia.delete_table(Person)
      Process.exit(pid, :kill)
    end
  end

  defp delete_tables(tables) do
    for table <- tables, :ets.whereis(table) != :undefined, do: :ets.delete(table)
  end
end
