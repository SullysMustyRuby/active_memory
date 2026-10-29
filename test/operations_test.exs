defmodule ActiveMemory.OperationsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ActiveMemory.Operations

  # The before_init methods under test. Each reports to the test process so a test
  # can see which ran, and in what order.
  def ok(pid, tag) do
    send(pid, {:ran, tag})
    {:ok, tag}
  end

  def fail(pid, tag) do
    send(pid, {:ran, tag})
    {:error, :no_source}
  end

  def log(event, %{config: %{pid: pid}}), do: send(pid, {:logged, event})

  describe "before_init/2" do
    test "returns {:ok, :default} for :default" do
      assert {:ok, :default} == Operations.before_init(:default, __MODULE__)
    end

    test "runs each method in order and treats any non-error return as success" do
      methods = [{:ok, [self(), :first]}, {:ok, [self(), :second]}]

      assert {:ok, :before_init_success} == Operations.before_init(methods, __MODULE__)
      assert_received {:ran, :first}
      assert_received {:ran, :second}
    end

    test "stops at a method that returns an error and skips the rest" do
      methods = [{:ok, [self(), :first]}, {:fail, [self(), :second]}, {:ok, [self(), :third]}]

      assert {:error, {:before_init, :fail, :no_source}} ==
               Operations.before_init(methods, __MODULE__)

      assert_received {:ran, :first}
      assert_received {:ran, :second}
      refute_received {:ran, :third}
    end

    test "accepts a single method tuple" do
      assert {:error, {:before_init, :fail, :no_source}} ==
               Operations.before_init({:fail, [self(), :only]}, __MODULE__)
    end
  end

  describe "before_init/3" do
    test "returns the error on a created table, without logging" do
      log =
        capture_log(fn ->
          assert {:error, {:before_init, :fail, :no_source}} ==
                   Operations.before_init([{:fail, [self(), :only]}], __MODULE__,
                     table: SomeTable,
                     table_status: :created
                   )
        end)

      refute log =~ "before_init failed"
    end

    test "logs the failure on a recovered table and reports success" do
      :ok = :logger.add_handler(:before_init_probe, __MODULE__, %{config: %{pid: self()}})
      on_exit(fn -> :logger.remove_handler(:before_init_probe) end)

      assert {:ok, :before_init_failed_on_recovery} ==
               Operations.before_init([{:fail, [self(), :only]}], __MODULE__,
                 table: SomeTable,
                 table_status: :recovered
               )

      assert_received {:logged, %{level: :warning, meta: meta}}

      assert %{
               active_memory_table: SomeTable,
               before_init_method: :fail,
               before_init_reason: :no_source
             } = meta
    end

    test "returns success on a recovered table when every method succeeds" do
      assert {:ok, :before_init_success} ==
               Operations.before_init([{:ok, [self(), :only]}], __MODULE__,
                 table: SomeTable,
                 table_status: :recovered
               )
    end
  end
end
