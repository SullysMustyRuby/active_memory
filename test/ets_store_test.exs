defmodule MnesiaCompanion.EtsStoreTest do
  use ExUnit.Case
  doctest MnesiaCompanion

  alias Test.Support.People.Person
  # alias Test.Support.People.Store, as: DogStore
  alias Test.Support.Dogs.Dog
  alias Test.Support.Dogs.Store, as: DogStore

  setup_all do
    {:ok, pid} = DogStore.start_link()
    {:ok, %{pid: pid}}
  end

  setup do
    on_exit(fn -> :ets.delete_all_objects(Dog) end)

    :ok
  end

  describe "all/0" do
    # test "retuns all records" do
    #   write_seeds()

    #   dogs = DogStore.all()

    #   assert length(dogs) == 10
    # end

    # test "returns empty list if table empty" do
    #   assert DogStore.all() == []
    # end
  end

  describe "delete/1" do
    #   setup do
    #     write_seeds()

    #     :ok
    #   end

    #   test "removes the record and returns ok" do
    #     {:ok, karl} = DogStore.one(%{first: "karl", last: "agathon"})

    #     assert DogStore.delete(karl) == :ok

    #     assert {:ok, nil} == DogStore.one(%{first: "karl", last: "agathon"})
    #   end

    #   test "returns ok for a record that does not exist" do
    #     {:ok, karl} = DogStore.one(%{first: "karl", last: "agathon"})

    #     assert DogStore.delete(karl) == :ok

    #     assert {:ok, nil} == DogStore.one(%{first: "karl", last: "agathon"})

    #     assert DogStore.delete(karl) == :ok
    #   end

    #   test "returns error for a record with a different schema" do
    #     dog = %Dog{
    #       breed: "PitBull",
    #       weight: 60,
    #       fixed?: "yes",
    #       name: "smegol"
    #     }

    #     assert DogStore.delete(dog) == {:error, :bad_schema}
    #   end
  end

  describe "one/1 with a map query" do
    #   setup do
    #     write_seeds()

    #     :ok
    #   end

    #   test "returns the record matching the query" do
    #     {:ok, record} = DogStore.one(%{first: "erin", last: "boeger"})

    #     assert record.first == "erin"
    #     assert record.last == "boeger"
    #   end

    #   test "returns nil list when no record matches" do
    #     assert {:ok, nil} == DogStore.one(%{first: "tiberious", last: "kirk"})
    #   end

    #   test "returns error when more than one record" do
    #     assert DogStore.one(%{hair_color: "brown", cylon?: false}) ==
    #              {:error, :more_than_one_result}
    #   end

    #   test "returns error when bad keys are in the query" do
    #     assert {:error, :query_schema_mismatch} ==
    #              DogStore.one(%{shoe_size: "13", lipstick: "pink"})
    #   end
  end

  describe "one/1 with a where query" do
    #   import MnesiaCompanion.Where

    #   setup do
    #     write_seeds()

    #     :ok
    #   end

    #   test "retuns the records that match a simple equals query" do
    #     query = where(:first == "erin" and :last == "boeger")
    #     {:ok, person} = DogStore.one(query)

    #     assert person.first == "erin"
    #     assert person.last == "boeger"
    #   end

    #   test "returns the records that match an 'and' query" do
    #     query = where(:hair_color == "bald" and :age > 98)
    #     {:ok, person} = DogStore.one(query)

    #     assert person.hair_color == "bald"
    #     assert person.first == "erin"
    #   end

    #   test "returns nil list when no record matches" do
    #     query = where(:first == "tiberious" and :last == "kirk")
    #     assert {:ok, nil} == DogStore.one(query)
    #   end

    #   test "returns error when more than one record" do
    #     query = where(:hair_color == "brown" and :cylon? == false)
    #     assert DogStore.one(query) == {:error, :more_than_one_result}
    #   end
  end

  describe "select/1 with a map query" do
    #   test "returns all records matching the query" do
    #     for hair_color <- ["bald", "blonde", "black", "blue"] do
    #       %Person{
    #         email: "#{hair_color}@here.com",
    #         first: "erin",
    #         last: "boeger",
    #         hair_color: hair_color
    #       }
    #       |> DogStore.write()
    #     end

    #     {:ok, [record]} = DogStore.select(%{hair_color: "blonde"})

    #     assert record.email == "blonde@here.com"
    #     assert record.hair_color == "blonde"

    #     {:ok, records} = DogStore.select(%{first: "erin", last: "boeger"})
    #     assert length(records) == 4

    #     for record <- records do
    #       assert record.first == "erin"
    #       assert record.last == "boeger"
    #     end
    # end

    #   test "returns nil when no records match" do
    #     assert {:ok, []} == DogStore.select(%{first: "tiberious", last: "kirk"})
    #   end

    #   test "returns error when bad keys are in the query" do
    #     assert {:error, :query_schema_mismatch} ==
    #              DogStore.select(%{shoe_size: "13", lipstick: "pink"})
    #   end
  end

  describe "select/1 with a where query" do
    #   import MnesiaCompanion.Where

    #   setup do
    #     write_seeds()

    #     :ok
    #   end

    #   test "retuns the records that match a simple equals query" do
    #     query = where(:cylon? == true)
    #     {:ok, people} = DogStore.select(query)

    #     assert length(people) == 3

    #     for person <- people do
    #       assert person.cylon?
    #     end
    #   end

    #   test "returns the records that match an 'and' query" do
    #     query = where(:hair_color == "brown" and :age > 45)
    #     {:ok, people} = DogStore.select(query)

    #     assert length(people) > 1

    #     for person <- people do
    #       assert person.hair_color == "brown"
    #       assert person.age > 45
    #     end
    #   end

    #   test "returns the records that match a multiple 'or' query" do
    #     query = where(:first == "erin" or :first == "laura" or :first == "galan")
    #     {:ok, people} = DogStore.select(query)

    #     assert length(people) == 3

    #     for person <- people do
    #       assert Enum.member?(["erin", "laura", "galan"], person.first)
    #     end
    #   end

    #   test "returns the records that match a multiple 'or' with 'and' query" do
    #     query = where(:cylon? == true or (:hair_color == "blonde" and :age < 50))
    #     {:ok, people} = DogStore.select(query)

    #     assert length(people) == 4

    #     for person <- people do
    #       if !person.cylon?, do: assert(person.hair_color == "blonde" && person.age < 50)
    #     end
    #   end

    #   test "returns records that match a !=" do
    #     query = where(:hair_color != "brown" and :age != 31)
    #     {:ok, people} = DogStore.select(query)

    #     assert length(people) == 3

    #     for person <- people do
    #       assert person.hair_color != "brown"
    #       assert person.age != 31
    #     end
    #   end
  end

  describe "withdraw/1 with a map query" do
    #   setup do
    #     write_seeds()

    #     :ok
    #   end

    #   test "returns the record matching the query and deletes the record" do
    #     {:ok, record} = DogStore.withdraw(%{first: "erin", last: "boeger"})

    #     assert record.first == "erin"
    #     assert record.last == "boeger"

    #     assert DogStore.one(%{first: "erin", last: "boeger"}) == {:ok, nil}
    #   end

    #   test "returns nil list when no record matches" do
    #     assert {:ok, nil} == DogStore.withdraw(%{first: "tiberious", last: "kirk"})
    #   end

    #   test "returns error when more than one record" do
    #     assert DogStore.withdraw(%{hair_color: "brown", cylon?: false}) ==
    #              {:error, :more_than_one_result}
    #   end

    #   test "returns error when bad keys are in the query" do
    #     assert {:error, :query_schema_mismatch} ==
    #              DogStore.withdraw(%{shoe_size: "13", lipstick: "pink"})
    #   end
  end

  describe "withdraw/1 with a where query" do
    #   import MnesiaCompanion.Where

    #   setup do
    #     write_seeds()

    #     :ok
    #   end

    #   test "retuns the records that match a simple equals query" do
    #     query = where(:first == "erin" and :last == "boeger")
    #     {:ok, person} = DogStore.withdraw(query)

    #     assert person.first == "erin"
    #     assert person.last == "boeger"

    #     assert DogStore.one(query) == {:ok, nil}
    #   end

    #   test "returns the records that match an 'and' query" do
    #     query = where(:hair_color == "bald" and :age > 98)
    #     {:ok, person} = DogStore.withdraw(query)

    #     assert person.hair_color == "bald"
    #     assert person.first == "erin"

    #     assert DogStore.one(query) == {:ok, nil}
    #   end

    #   test "returns nil list when no record matches" do
    #     query = where(:first == "tiberious" and :last == "kirk")
    #     assert {:ok, nil} == DogStore.withdraw(query)
    #   end

    #   test "returns error when more than one record" do
    #     query = where(:hair_color == "brown" and :cylon? == false)
    #     assert DogStore.withdraw(query) == {:error, :more_than_one_result}
    #   end
  end

  describe "write/1" do
    test "writes the record with the correct schema" do
      record =
        %Dog{
          breed: "Shaggy Black Lab",
          weight: "30",
          fixed?: false,
          name: "gem"
        }
        |> Dog.new()

      assert DogStore.all() == []
      assert {:ok, record} == DogStore.write(record)
      assert DogStore.all() == [record]
    end

    #   test "returns error for a record with no schema" do
    #     record = %{email: "test@here.com", first: "erin", last: "boeger", hair_color: "bald"}

    #     assert {:error, :bad_schema} == DogStore.write(record)
    #   end

    #   test "returns error for a record with a different schema" do
    #     dog = %Dog{
    #       breed: "PitBull",
    #       weight: 60,
    #       fixed?: "yes",
    #       name: "smegol"
    #     }

    #     assert {:error, :bad_schema} == DogStore.write(dog)
    #   end
  end

  defp write_seeds do
    {seeds, _} =
      File.cwd!()
      |> Path.join(["/test/support/dogs/", "dog_seeds.exs"])
      |> Code.eval_file()

    Enum.each(seeds, fn seed -> Dog.new(seed) |> DogStore.write() end)
  end
end
