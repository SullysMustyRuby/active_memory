defmodule ActiveMemory.Adapters.Mnesia.MigrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  By default these tests are skipped becasue they cause errors. 
  To run these tests make sure the empd daemon is running.
  In your terminal:
  ```bash
  $ epmd -daemon
  ```
  In test_helper.exs uncomment the following line:
  ```elixir
  # :ok = LocalCluster.start()
  ```
  Don`t forget to commnt out the line above when completed.
  then run:
  ```elixir
    mix test test/adapters/mnesia/migration_test.exs --include migration
  ```

  """

  alias Test.Support.People.{Person, Store}
  alias Test.Support.Whales.Store, as: WhaleStore
  alias Test.Support.Whales.Whale

  describe "migrate_table_options/1" do
    setup do
      File.cwd!() |> Path.join("Mnesia.manager@127.0.0.1") |> File.rm_rf()

      on_exit(fn -> File.cwd!() |> Path.join("Mnesia.manager@127.0.0.1") |> File.rm_rf() end)

      {:ok, %{}}
    end

    @tag :migration
    test "updates the access_mode on startup" do
      assert :mnesia.create_table(Person,
               access_mode: :read_only,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               ram_copies: [node()],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :access_mode) == :read_only

      {:ok, _pid} = Store.start_link()

      assert :mnesia.table_info(Person, :access_mode) == :read_write
    end

    @tag :migration
    test "updates the disc copies on startup" do
      [app_instance] = LocalCluster.start_nodes("app_instance", 1)

      {[:stopped, :stopped], []} = :rpc.multicall(:mnesia, :stop, [])
      :ok = :mnesia.delete_schema([Node.self() | Node.list()])
      :ok = :mnesia.create_schema([node()])
      {[:ok, :ok], []} = :rpc.multicall(:mnesia, :start, [])

      assert :mnesia.create_table(Person,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               disc_copies: [node()],
               ram_copies: [app_instance],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :disc_copies) == [node()]

      {:ok, _pid} = Store.start_link()

      assert :mnesia.table_info(Person, :disc_copies) == []
      assert :mnesia.table_info(Person, :ram_copies) == [node()]

      :ok = LocalCluster.stop_nodes([app_instance])
    end

    @tag :migration
    test "updates the disc_only_copies on startup" do
      [app_instance] = LocalCluster.start_nodes("app_instance", 1)

      {[:stopped, :stopped], []} = :rpc.multicall(:mnesia, :stop, [])
      :ok = :mnesia.delete_schema([Node.self() | Node.list()])
      :ok = :mnesia.create_schema([node()])
      {[:ok, :ok], []} = :rpc.multicall(:mnesia, :start, [])

      assert :mnesia.create_table(Person,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               disc_only_copies: [node()],
               ram_copies: [app_instance],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :disc_only_copies) == [:"manager@127.0.0.1"]

      {:ok, _pid} = Store.start_link()

      assert :mnesia.table_info(Person, :disc_only_copies) == []
      assert :mnesia.table_info(Person, :ram_copies) == [:"manager@127.0.0.1"]

      :ok = LocalCluster.stop_nodes([app_instance])
    end

    @tag :migration
    test "removes the local ram_copy on startup" do
      [app_instance] = LocalCluster.start_nodes("app_instance", 1)

      :stopped = :mnesia.stop()
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()

      assert :mnesia.create_table(Whale,
               attributes: [:email, :first, :last, :hair_color, :age],
               index: [:first, :last],
               ram_copies: [node()],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Whale, :ram_copies) == [:"manager@127.0.0.1"]

      {:ok, _pid} = WhaleStore.start_link()

      assert :mnesia.table_info(Whale, :ram_copies) == [app_instance]

      :ok = LocalCluster.stop_nodes([app_instance])
    end

    @tag :migration
    test "replaces the indexes on startup" do
      :stopped = :mnesia.stop()
      :ok = :mnesia.delete_schema([node()])
      :ok = :mnesia.start()

      assert :mnesia.create_table(Person,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               index: [:email, :first],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :index) == [4, 3]

      {:ok, pid} = Store.start_link()

      assert :mnesia.table_info(Person, :index) == [8, 5]

      Process.exit(pid, :kill)
    end

    @tag :migration
    test "adds new indexes on startup if none exist" do
      :stopped = :mnesia.stop()
      :ok = :mnesia.delete_schema([node()])
      :ok = :mnesia.start()

      assert :mnesia.create_table(Person,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :index) == []

      {:ok, pid} = Store.start_link()

      assert :mnesia.table_info(Person, :index) == [8, 5]

      Process.exit(pid, :kill)
    end

    @tag :migration
    test "removes old indexes on startup" do
      :stopped = :mnesia.stop()
      :ok = :mnesia.delete_schema([node()])
      :ok = :mnesia.start()

      assert :mnesia.create_table(Person,
               index: [:last, :first, :cylon?],
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :index) == [8, 4, 5]

      {:ok, pid} = Store.start_link()

      assert :mnesia.table_info(Person, :index) == [5, 8]

      Process.exit(pid, :kill)
    end

    @tag :migration
    test "updates the migrate load order on startup" do
      :stopped = :mnesia.stop()
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()

      assert :mnesia.create_table(Person,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               load_order: 5,
               type: :set
             ) == {:atomic, :ok}

      assert :mnesia.table_info(Person, :load_order) == 5

      {:ok, pid} = Store.start_link()

      assert :mnesia.table_info(Person, :load_order) == 0

      Process.exit(pid, :kill)
    end

    @tag :migration
    test "updates the majority on startup" do
      :stopped = :mnesia.stop()
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()

      assert :mnesia.create_table(Person,
               attributes: [:uuid, :email, :first, :last, :hair_color, :age, :cylon?],
               index: [:last, :cylon?],
               majority: true,
               type: :set
             ) == {:atomic, :ok}

      info = :mnesia.table_info(Person, :all)

      assert Keyword.get(info, :majority)

      {:ok, pid} = Store.start_link()

      updated = :mnesia.table_info(Person, :all)

      refute Keyword.get(updated, :majority)

      Process.exit(pid, :kill)
    end
  end
end
