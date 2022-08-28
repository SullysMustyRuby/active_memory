defmodule ActiveMemory.Adapters.Mnesia.MigrationTest do
  use ExUnit.Case, async: false

  alias Test.Support.People.{Person, Store}
  # alias Test.Support.Whales.{Whale, Store}

  describe "migrate_table_options/1" do
    test "updates the access_mode on startup" do
      assert :mnesia.create_table(Person,
               access_mode: :read_only,
               attributes: [:email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               ram_copies: [node()],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :access_mode) == :read_only

      {:ok, pid} = Store.start_link()

      assert :mnesia.table_info(Person, :access_mode) == :read_write

      Process.exit(pid, :kill)
    end

    test "updates the disc copies on startup" do
      assert :mnesia.stop() == :ok
      assert :mnesia.create_schema() == :ok
      assert :mnesia.start() == :ok

      assert :mnesia.create_table(Person,
               access_mode: :read_only,
               attributes: [:email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               disc_copies: [node()],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :disc_copies) == [node()]

      {:ok, pid} = Store.start_link()

      assert :mnesia.table_info(Person, :disc_copies) == []

      Process.exit(pid, :kill)
    end
  end
end
