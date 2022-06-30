defmodule ActiveMemory.StoreTest do
  use ExUnit.Case, async: false

  alias Test.Support.People.Store, as: PeopleStore

  describe "init with seeds" do
    test "with a valid seed file populates the store" do
      {:ok, pid} = PeopleStore.start_link()

      people = PeopleStore.all()
      assert length(people) == 10

      Process.exit(pid, :kill)
    end
  end
end
