defmodule MnesiaCompanion.StoreTest do
  use ExUnit.Case
  doctest MnesiaCompanion

  defmodule Tester do
    use Memento.Table, attributes: [:email, :first, :last, :hair_color]
  end

  defmodule Tester.Store do
    use MnesiaCompanion.Store, table: Tester
  end

  defmodule BadSchema do
    defstruct [:email, :first, :last, :hair_color]
  end

  setup_all do
    {:ok, pid} = Tester.Store.start_link()
    {:ok, %{pid: pid}}
  end

  setup do
    on_exit(fn -> :mnesia.clear_table(Tester) end)

    :ok
  end

  describe "get/1" do
    alias MnesiaCompanion.StoreTest.Tester

    test "returns all records matching the query" do
      for hair_color <- ["bald", "blonde", "black", "blue"] do
        %Tester{
          email: "#{hair_color}@here.com",
          first: "erin",
          last: "boeger",
          hair_color: hair_color
        }
        |> Tester.Store.insert()
      end

      {:ok, [record]} = Tester.Store.get(%{hair_color: "blonde"})

      assert record.email == "blonde@here.com"
      assert record.hair_color == "blonde"

      {:ok, records} = Tester.Store.get(%{first: "erin", last: "boeger"})
      assert length(records) == 4

      for record <- records do
        assert record.first == "erin"
        assert record.last == "boeger"
      end
    end

    test "returns empty list when no records match" do
      for hair_color <- ["bald", "blonde", "black", "blue"] do
        %Tester{
          email: "#{hair_color}@here.com",
          first: "erin",
          last: "boeger",
          hair_color: hair_color
        }
        |> Tester.Store.insert()
      end

      assert length(Tester.Store.all()) == 4

      assert {:ok, []} == Tester.Store.get(%{first: "tiberious", last: "kirk"})
    end

    test "returns error when bad keys are in the query" do
      assert {:error, :query_schema_mismatch} ==
               Tester.Store.get(%{shoe_size: "13", lipstick: "pink"})
    end
  end

  describe "insert/1" do
    alias MnesiaCompanion.StoreTest.Tester

    test "inserts the record with the correct schema" do
      record = %Tester{
        email: "test@here.com",
        first: "erin",
        last: "boeger",
        hair_color: "bald"
      }

      assert Tester.Store.all() == []
      assert {:ok, record} == Tester.Store.insert(record)
      assert Tester.Store.all() == [record]
    end

    test "returns error for a record with no schema" do
      record = %{email: "test@here.com", first: "erin", last: "boeger", hair_color: "bald"}

      assert {:error, :bad_schema} == Tester.Store.insert(record)
    end

    test "returns error for a record with a different schema" do
      record = %BadSchema{
        email: "test@here.com",
        first: "erin",
        last: "boeger",
        hair_color: "bald"
      }

      assert {:error, :bad_schema} == Tester.Store.insert(record)
    end
  end
end
