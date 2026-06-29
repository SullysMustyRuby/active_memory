defmodule ActiveMemory.TtlTest do
  use ExUnit.Case, async: false

  alias Test.Support.ProcessHelper
  alias Test.Support.Ttl.Repo, as: TtlRepo
  alias Test.Support.Ttl.Session
  alias Test.Support.Ttl.Token
  alias Test.Support.Ttl.TokenStore

  # Token/Session use ttl: 50ms with a 300ms sweep interval, giving a wide window
  # to observe lazy filtering (record still present, not returned) separately from
  # the sweep (record removed).

  describe "Store with ttl (ETS)" do
    setup do
      ProcessHelper.stop(TokenStore)
      {:ok, _pid} = TokenStore.start_link()

      on_exit(fn ->
        ProcessHelper.stop(TokenStore)

        case :ets.whereis(Token) do
          :undefined -> :ok
          _table_ref -> :ets.delete(Token)
        end
      end)

      :ok
    end

    test "a record is readable before it expires" do
      {:ok, _record} = TokenStore.write(%Token{name: "t1", value: "v"})

      assert {:ok, token} = TokenStore.one(%{name: "t1"})
      assert token.value == "v"
    end

    test "an expired record is not returned, and remains until swept (lazy)" do
      {:ok, _record} = TokenStore.write(%Token{name: "t2", value: "v"})

      Process.sleep(120)

      assert TokenStore.one(%{name: "t2"}) == {:error, :not_found}
      # lazily filtered on read, but not yet reclaimed (sweep interval is 300ms)
      assert :ets.info(Token, :size) == 1
    end

    test "expired records are swept from the table" do
      {:ok, _record} = TokenStore.write(%Token{name: "t3", value: "v"})
      assert :ets.info(Token, :size) == 1

      Process.sleep(500)

      assert :ets.info(Token, :size) == 0
    end
  end

  describe "ActiveRepo with ttl (Mnesia)" do
    setup do
      ProcessHelper.stop(TtlRepo)
      {:ok, _pid} = TtlRepo.start_link()

      on_exit(fn ->
        ProcessHelper.stop(TtlRepo)
        :mnesia.delete_table(Session)
      end)

      :ok
    end

    test "a record is readable before it expires" do
      {:ok, _record} = TtlRepo.write(%Session{name: "s1", value: "v"})

      assert {:ok, session} = TtlRepo.one(Session, %{name: "s1"})
      assert session.value == "v"
    end

    test "an expired record is not returned, and remains until swept (lazy)" do
      {:ok, _record} = TtlRepo.write(%Session{name: "s2", value: "v"})

      Process.sleep(120)

      assert TtlRepo.one(Session, %{name: "s2"}) == {:error, :not_found}
      assert :mnesia.table_info(Session, :size) == 1
    end

    test "expired records are swept from the table" do
      {:ok, _record} = TtlRepo.write(%Session{name: "s3", value: "v"})
      assert :mnesia.table_info(Session, :size) == 1

      Process.sleep(500)

      assert :mnesia.table_info(Session, :size) == 0
    end
  end
end
