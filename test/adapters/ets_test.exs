defmodule ActiveMemory.Adapters.EtsTest do
  use ExUnit.Case, async: false
  doctest ActiveMemory

  alias Test.Support.Dogs.Dog
  alias Test.Support.Dogs.Store, as: DogStore
  alias Test.Support.People.Person

  import ActiveMemory.Query

  setup_all do
    {:ok, pid} = DogStore.start_link()

    on_exit(fn -> Process.exit(pid, :kill) end)

    {:ok, %{pid: pid}}
  end

  setup do
    on_exit(fn -> :ets.delete_all_objects(Dog) end)

    :ok
  end

  describe "all/0" do
    test "retuns all records" do
      write_seeds()
      dogs = DogStore.all()

      assert length(dogs) == 11
    end

    test "returns empty list if table empty" do
      assert DogStore.all() == []
    end
  end

  describe "delete/1" do
    setup do
      write_seeds()

      :ok
    end

    test "removes the record and returns ok" do
      {:ok, dog} = DogStore.one(%{name: "poopsie", breed: "Poodle"})

      assert DogStore.delete(dog) == :ok

      assert {:ok, nil} == DogStore.one(%{name: "poopsie", breed: "Poodle"})
    end

    test "returns ok for a record that does not exist" do
      {:ok, poopsie} = DogStore.one(%{name: "poopsie", breed: "Poodle"})
      assert DogStore.delete(poopsie) == :ok

      assert {:ok, nil} == DogStore.one(%{name: "poopsie", breed: "Poodle"})
      assert DogStore.delete(poopsie) == :ok
    end

    test "returns error for a record with a different schema" do
      person = %Person{
        email: "erin@galactica.com",
        first: "erin",
        last: "boeger",
        hair_color: "bald",
        age: 99,
        cylon?: true
      }

      assert DogStore.delete(person) == {:error, :bad_schema}
    end
  end

  describe "one/1 with a map query" do
    setup do
      write_seeds()
      :ok
    end

    test "returns the record matching the query" do
      {:ok, dog} = DogStore.one(%{name: "gem", breed: "Shaggy Black Lab"})

      assert dog.name == "gem"
      assert dog.breed == "Shaggy Black Lab"
    end

    test "returns nil when no record matches" do
      assert {:ok, nil} == DogStore.one(%{breed: "wolf", name: "tiberious"})
    end

    test "returns error when more than one record" do
      assert DogStore.one(%{breed: "PitBull", weight: 60}) ==
               {:error, :more_than_one_result}
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               DogStore.one(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "one/1 with a match query" do
    setup do
      write_seeds()

      :ok
    end

    test "retuns the records that match a simple equals query" do
      query = match(:name == "gem" and :breed == "Shaggy Black Lab")
      {:ok, dog} = DogStore.one(query)

      assert dog.name == "gem"
      assert dog.breed == "Shaggy Black Lab"
    end

    test "returns the records that match an 'and' query" do
      query = match(:breed == "Husky" and :weight >= 50)
      {:ok, dog} = DogStore.one(query)

      assert dog.breed == "Husky"
      assert dog.weight >= 50
    end

    test "returns nil list when no record matches" do
      query = match(:name == "tiberious" and :breed == "Wolf")
      assert {:ok, nil} == DogStore.one(query)
    end

    test "returns error when more than one record" do
      query = match(:breed == "PitBull" and :fixed? == true)
      assert DogStore.one(query) == {:error, :more_than_one_result}
    end
  end

  describe "select/1 with a map query" do
    setup do
      write_seeds()
      :ok
    end

    test "returns all records matching the query" do
      {:ok, [record]} = DogStore.select(%{breed: "Husky"})

      assert record.breed == "Husky"

      {:ok, records} = DogStore.select(%{breed: "PitBull", fixed?: true})
      assert length(records) == 2

      for record <- records do
        assert record.breed == "PitBull"
        assert record.fixed?
      end
    end

    test "returns nil when no records match" do
      assert {:ok, []} == DogStore.select(%{breed: "wolf", name: "tiberious"})
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               DogStore.select(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "select/1 with a match query" do
    setup do
      write_seeds()

      :ok
    end

    test "retuns the records that match a simple equals query" do
      query = match(:fixed? == false)

      {:ok, dogs} = DogStore.select(query)

      assert length(dogs) == 8

      for dog <- dogs do
        refute dog.fixed?
      end
    end

    test "returns the records that match an 'and' query" do
      query = match(:breed == "PitBull" and :weight > 45)
      {:ok, dogs} = DogStore.select(query)

      assert length(dogs) > 2

      for dog <- dogs do
        assert dog.breed == "PitBull"
        assert dog.weight > 45
      end
    end

    test "suceeds with a variable in the match" do
      weight = 40
      query = match(:weight <= weight)
      {:ok, dogs} = DogStore.select(query)

      for dog <- dogs do
        assert dog.weight <= 40
      end
    end

    test "returns the records that match a multiple 'or' query" do
      weight = 50
      query = match(:breed == "PitBull" or :breed == "Labrador" or :weight >= weight)

      {:ok, dogs} = DogStore.select(query)

      assert length(dogs) == 6

      for dog <- dogs do
        assert Enum.member?(["PitBull", "Labrador"], dog.breed) || dog.weight >= 50
      end
    end

    test "returns the records that match a multiple 'or' with 'and' query" do
      query = match(:fixed? == true or (:breed == "Labrador" and :weight <= 45))
      {:ok, dogs} = DogStore.select(query)

      assert length(dogs) == 2

      for dog <- dogs do
        assert dog.fixed? == true or dog.breed == "Labrador" or dog.weight <= 45
      end
    end

    test "returns records that match a <= and !=" do
      query = match(:breed != "PitBull" and :weight <= 30)
      {:ok, dogs} = DogStore.select(query)

      assert length(dogs) == 2

      for dog <- dogs do
        assert dog.breed != "PitBull"
        assert dog.weight <= 30
      end
    end

    test "returns records that match a !=" do
      query = match(:breed != "Poodle" and :weight != 60)
      {:ok, dogs} = DogStore.select(query)

      assert length(dogs) == 4

      for dog <- dogs do
        assert dog.breed != "Poodle"
        assert dog.weight != 60
      end
    end
  end

  describe "withdraw/1 with a map query" do
    setup do
      write_seeds()

      :ok
    end

    test "returns the record matching the query and deletes the record" do
      {:ok, dog} = DogStore.withdraw(%{name: "codo", breed: "Husky"})

      assert dog.name == "codo"
      assert dog.breed == "Husky"

      assert DogStore.one(%{name: "codo", breed: "Husky"}) == {:ok, nil}
    end

    test "returns nil list when no dog matches" do
      assert {:ok, nil} == DogStore.withdraw(%{name: "tiberious", breed: "T-Rex"})
    end

    test "returns error when more than one dog" do
      assert DogStore.withdraw(%{breed: "PitBull", fixed?: true}) ==
               {:error, :more_than_one_result}
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               DogStore.withdraw(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "withdraw/1 with a match query" do
    setup do
      write_seeds()

      :ok
    end

    test "retuns the dogs that match a simple equals query" do
      query = match(:name == "gem" and :breed == "Shaggy Black Lab")
      {:ok, dog} = DogStore.withdraw(query)

      assert dog.name == "gem"
      assert dog.breed == "Shaggy Black Lab"

      assert DogStore.one(query) == {:ok, nil}
    end

    test "returns the dogs that match an 'and' query" do
      query = match(:breed == "schnauzer" and :name == "bill")
      {:ok, dog} = DogStore.withdraw(query)

      assert dog.breed == "schnauzer"
      assert dog.name == "bill"

      assert DogStore.one(query) == {:ok, nil}
    end

    test "returns nil list when no dog matches" do
      query = match(:name == "tiberious" and :breed == "T-Rex")
      assert {:ok, nil} == DogStore.withdraw(query)
    end

    test "returns error when more than one dog" do
      query = match(:breed == "PitBull" and :fixed? == true)
      assert DogStore.withdraw(query) == {:error, :more_than_one_result}
    end
  end

  describe "write/1" do
    test "writes the record with the correct schema" do
      record = %Dog{
        breed: "Shaggy Black Lab",
        weight: "30",
        fixed?: false,
        name: "gem"
      }

      assert DogStore.all() == []
      {:ok, _record} = DogStore.write(record)
      [new_record] = DogStore.all()
      assert new_record.breed == "Shaggy Black Lab"
      assert new_record.weight == "30"
      assert new_record.fixed? == false
      assert new_record.name == "gem"
      assert new_record.uuid != nil
    end

    test "returns error for a record with no schema" do
      record = %{breed: "Shaggy Black Lab", weight: "30", fixed?: false, name: "gem"}

      assert {:error, :bad_schema} == DogStore.write(record)
    end

    test "returns error for a record with a different schema" do
      person = %Person{
        email: "erin@galactica.com",
        first: "erin",
        last: "boeger",
        hair_color: "bald",
        age: 99,
        cylon?: true
      }

      assert {:error, :bad_schema} == DogStore.write(person)
    end
  end

  defp write_seeds do
    {seeds, _} =
      File.cwd!()
      |> Path.join(["/test/support/dogs/", "dog_seeds.exs"])
      |> Code.eval_file()

    Enum.each(seeds, fn seed -> DogStore.write(seed) end)
  end
end
