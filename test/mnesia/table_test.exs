defmodule ActiveMemory.Mneisa.TableTest do
  use ExUnit.Case
  doctest ActiveMemory

  # alias Test.Support.People.Person
  # alias Test.Support.People.Store, as: PeopleStore

  # setup_all do
  #   _ = :os.cmd('epmd -daemon')
  #   {:ok, master} = Node.start(:master@localhost, :shortnames)

  #   {:ok, %{master: master}}
  # end

  # describe "create/1" do
  #   test "with no existing table creates a new table" do
  #     info =
  #       try do
  #         :mnesia.table_info(Person, :attributes)
  #       catch
  #         :exit, {:aborted, message} -> message
  #       end

  #     assert info == {:no_exists, Test.Support.People.Person, :attributes}
  #     assert Person.create(Person) == :ok
  #   end

  #   test "with an existing table copies the table" do
  #     {:ok, slave} = :slave.start_link(:localhost, 'slave')

  #     :mnesia.stop()
  #     :mnesia.start()

  #     require IEx
  #     IEx.pry()
  #     Memento.Table.create(Person, [{:ram_copies, [slave]}])

  #     # :mnesia.start()
  #     # Node.spawn(slave, fn -> :mnesia.create_table(Person, ram_copies: [slave]) end)
  #   end
  # end
end
