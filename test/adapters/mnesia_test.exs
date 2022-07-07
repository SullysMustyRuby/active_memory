defmodule ActiveMemory.Adapters.MneisaTest do
  use ExUnit.Case
  doctest ActiveMemory

  alias Test.Support.People.Person
  alias Test.Support.People.Store, as: PeopleStore
  alias Test.Support.Dogs.Dog

  setup_all do
    {:ok, pid} = PeopleStore.start_link()

    on_exit(fn -> :mnesia.delete_table(Person) end)
    on_exit(fn -> Process.exit(pid, :kill) end)

    {:ok, %{pid: pid}}
  end

  setup do
    on_exit(fn -> :mnesia.clear_table(Person) end)

    :ok
  end

  describe "all/0" do
    test "retuns all records" do
      write_seeds()
      people = PeopleStore.all()

      assert length(people) == 10

      for person <- people do
        assert person.__struct__ == Person
      end
    end

    test "returns empty list if table empty" do
      assert PeopleStore.all() == []
    end
  end

  describe "delete/1" do
    setup do
      write_seeds()

      :ok
    end

    test "removes the record and returns ok" do
      {:ok, karl} = PeopleStore.one(%{first: "karl", last: "agathon"})

      assert PeopleStore.delete(karl) == :ok

      assert {:ok, nil} == PeopleStore.one(%{first: "karl", last: "agathon"})
    end

    test "returns ok for a record that does not exist" do
      {:ok, karl} = PeopleStore.one(%{first: "karl", last: "agathon"})

      assert PeopleStore.delete(karl) == :ok

      assert {:ok, nil} == PeopleStore.one(%{first: "karl", last: "agathon"})

      assert PeopleStore.delete(karl) == :ok
    end

    test "returns error for a record with a different schema" do
      dog = %Dog{
        breed: "PitBull",
        weight: 60,
        fixed?: "yes",
        name: "smegol"
      }

      assert PeopleStore.delete(dog) == {:error, :bad_schema}
    end
  end

  describe "one/1 with a map query" do
    setup do
      write_seeds()

      :ok
    end

    test "returns the record matching the query" do
      {:ok, record} = PeopleStore.one(%{first: "erin", last: "boeger"})

      assert record.first == "erin"
      assert record.last == "boeger"
    end

    test "returns nil list when no record matches" do
      assert {:ok, nil} == PeopleStore.one(%{first: "tiberious", last: "kirk"})
    end

    test "returns error when more than one record" do
      assert PeopleStore.one(%{hair_color: "brown", cylon?: false}) ==
               {:error, :more_than_one_result}
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               PeopleStore.one(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "one/1 with a match query" do
    import ActiveMemory.Query

    setup do
      write_seeds()

      :ok
    end

    test "retuns the records that match a simple equals query" do
      query = match(:first == "erin" and :last == "boeger")
      {:ok, person} = PeopleStore.one(query)

      assert person.first == "erin"
      assert person.last == "boeger"
    end

    test "returns the records that match an 'and' query" do
      query = match(:hair_color == "bald" and :age > 98)
      {:ok, person} = PeopleStore.one(query)

      assert person.hair_color == "bald"
      assert person.first == "erin"
    end

    test "returns nil list when no record matches" do
      query = match(:first == "tiberious" and :last == "kirk")
      assert {:ok, nil} == PeopleStore.one(query)
    end

    test "returns error when more than one record" do
      query = match(:hair_color == "brown" and :cylon? == false)
      assert PeopleStore.one(query) == {:error, :more_than_one_result}
    end
  end

  describe "select/1 with a map query" do
    test "returns all records matching the query" do
      for hair_color <- ["bald", "blonde", "black", "blue"] do
        %Person{
          email: "#{hair_color}@here.com",
          first: "erin",
          last: "boeger",
          hair_color: hair_color
        }
        |> PeopleStore.write()
      end

      {:ok, [record]} = PeopleStore.select(%{hair_color: "blonde"})

      assert record.email == "blonde@here.com"
      assert record.hair_color == "blonde"

      {:ok, records} = PeopleStore.select(%{first: "erin", last: "boeger"})
      assert length(records) == 4

      for record <- records do
        assert record.first == "erin"
        assert record.last == "boeger"
      end
    end

    test "returns nil when no records match" do
      assert {:ok, []} == PeopleStore.select(%{first: "tiberious", last: "kirk"})
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               PeopleStore.select(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "select/1 with a match query" do
    import ActiveMemory.Query

    setup do
      write_seeds()

      :ok
    end

    test "retuns the records that match a simple equals query" do
      query = match(:cylon? == true)
      {:ok, people} = PeopleStore.select(query)

      assert length(people) == 3

      for person <- people do
        assert person.cylon?
      end
    end

    test "returns the records that match an 'and' query" do
      query = match(:hair_color == "brown" and :age > 45)
      {:ok, people} = PeopleStore.select(query)

      assert length(people) > 1

      for person <- people do
        assert person.hair_color == "brown"
        assert person.age > 45
      end
    end

    test "returns the records that match a multiple 'or' query" do
      query = match(:first == "erin" or :first == "laura" or :first == "galan")
      {:ok, people} = PeopleStore.select(query)

      assert length(people) == 3

      for person <- people do
        assert Enum.member?(["erin", "laura", "galan"], person.first)
      end
    end

    test "returns the records that match a multiple 'or' with 'and' query" do
      query = match(:cylon? == true or (:hair_color == "blonde" and :age < 50))
      {:ok, people} = PeopleStore.select(query)

      assert length(people) == 4

      for person <- people do
        if !person.cylon?, do: assert(person.hair_color == "blonde" && person.age < 50)
      end
    end

    test "returns records that match a !=" do
      query = match(:hair_color != "brown" and :age != 31)
      {:ok, people} = PeopleStore.select(query)

      assert length(people) == 3

      for person <- people do
        assert person.hair_color != "brown"
        assert person.age != 31
      end
    end
  end

  describe "withdraw/1 with a map query" do
    setup do
      write_seeds()

      :ok
    end

    test "returns the record matching the query and deletes the record" do
      {:ok, record} = PeopleStore.withdraw(%{first: "erin", last: "boeger"})

      assert record.first == "erin"
      assert record.last == "boeger"

      assert PeopleStore.one(%{first: "erin", last: "boeger"}) == {:ok, nil}
    end

    test "returns nil list when no record matches" do
      assert {:ok, nil} == PeopleStore.withdraw(%{first: "tiberious", last: "kirk"})
    end

    test "returns error when more than one record" do
      assert PeopleStore.withdraw(%{hair_color: "brown", cylon?: false}) ==
               {:error, :more_than_one_result}
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               PeopleStore.withdraw(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "withdraw/1 with a match query" do
    import ActiveMemory.Query

    setup do
      write_seeds()

      :ok
    end

    test "retuns the records that match a simple equals query" do
      query = match(:first == "erin" and :last == "boeger")
      {:ok, person} = PeopleStore.withdraw(query)

      assert person.first == "erin"
      assert person.last == "boeger"

      assert PeopleStore.one(query) == {:ok, nil}
    end

    test "returns the records that match an 'and' query" do
      query = match(:hair_color == "bald" and :age > 98)
      {:ok, person} = PeopleStore.withdraw(query)

      assert person.hair_color == "bald"
      assert person.first == "erin"

      assert PeopleStore.one(query) == {:ok, nil}
    end

    test "returns nil list when no record matches" do
      query = match(:first == "tiberious" and :last == "kirk")
      assert {:ok, nil} == PeopleStore.withdraw(query)
    end

    test "returns error when more than one record" do
      query = match(:hair_color == "brown" and :cylon? == false)
      assert PeopleStore.withdraw(query) == {:error, :more_than_one_result}
    end
  end

  describe "write/1" do
    test "writes the record with the correct schema" do
      record = %Person{
        email: "test@here.com",
        first: "erin",
        last: "boeger",
        hair_color: "bald"
      }

      assert PeopleStore.all() == []
      assert {:ok, record} == PeopleStore.write(record)
      assert PeopleStore.all() == [record]
    end

    test "returns error for a record with no schema" do
      record = %{email: "test@here.com", first: "erin", last: "boeger", hair_color: "bald"}

      assert {:error, :bad_schema} == PeopleStore.write(record)
    end

    test "returns error for a record with a different schema" do
      dog = %Dog{
        breed: "PitBull",
        weight: 60,
        fixed?: "yes",
        name: "smegol"
      }

      assert {:error, :bad_schema} == PeopleStore.write(dog)
    end
  end

  defp write_seeds do
    {seeds, _} =
      File.cwd!()
      |> Path.join(["/test/support/people/", "person_seeds.exs"])
      |> Code.eval_file()

    Enum.each(seeds, fn seed -> PeopleStore.write(seed) end)
  end
end
