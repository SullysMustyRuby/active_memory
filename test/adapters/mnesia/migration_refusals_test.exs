# A table asking for a disc copy on a node whose Mnesia runs without a disc
# schema — the test environment, and any app that never ran create_schema. The
# change is refused at runtime ({:aborted, {:has_no_disc, node}}); the refusal
# must be logged and skipped, not raised.
defmodule Test.Support.Migration.DiscWithoutSchema do
  use ActiveMemory.Table,
    options: [disc_copies: [node()]]

  attributes do
    field(:name)
    field(:size)
  end
end

defmodule Test.Support.Migration.DiscWithoutSchemaStore do
  use ActiveMemory.Store,
    table: Test.Support.Migration.DiscWithoutSchema
end

# A valid mix of copy types. The old pipeline leaked the validation result into
# Keyword.get/3 and crashed on any table naming more than one copy type.
defmodule Test.Support.Migration.MixedCopies do
  use ActiveMemory.Table,
    options: [ram_copies: [node()], disc_only_copies: [:ghost@nohost]]

  attributes do
    field(:name)
    field(:size)
  end
end

# The same node under two copy types: a configuration bug, so it raises.
defmodule Test.Support.Migration.OverlappingCopies do
  use ActiveMemory.Table,
    options: [ram_copies: [node()], disc_copies: [node()]]

  attributes do
    field(:name)
    field(:size)
  end
end

defmodule ActiveMemory.Adapters.Mnesia.MigrationRefusalsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ActiveMemory.Adapters.Mnesia.Migration
  alias Test.Support.Migration.DiscWithoutSchema
  alias Test.Support.Migration.DiscWithoutSchemaStore
  alias Test.Support.Migration.MixedCopies
  alias Test.Support.Migration.OverlappingCopies
  alias Test.Support.ProcessHelper

  # Every table here is created directly, with plain local options, so that the
  # migration runs against an existing table whose options differ from the code —
  # the situation migrate_table_options/1 exists for.
  defp create_existing(table) do
    {:atomic, :ok} = :mnesia.create_table(table, attributes: [:name, :size])

    on_exit(fn -> :mnesia.delete_table(table) end)

    :ok
  end

  describe "a copy change Mnesia refuses at runtime" do
    setup do: create_existing(DiscWithoutSchema)

    test "is logged and skipped rather than raised" do
      log =
        capture_log(fn ->
          assert Migration.migrate_table_options(DiscWithoutSchema) == :ok
        end)

      assert log =~ "could not change"
      assert log =~ "has_no_disc"
      assert log =~ "keeps its current setting"

      # the replica stays a ram copy
      assert :mnesia.table_info(DiscWithoutSchema, :ram_copies) == [node()]
    end

    test "does not keep the store from starting" do
      ProcessHelper.stop(DiscWithoutSchemaStore)

      log =
        capture_log(fn ->
          assert {:ok, pid} = DiscWithoutSchemaStore.start_link()

          on_exit(fn -> ProcessHelper.stop(DiscWithoutSchemaStore) end)

          assert Process.alive?(pid)
        end)

      assert log =~ "could not change"

      # the table is usable despite the refused change
      {:ok, written} =
        DiscWithoutSchemaStore.write(%DiscWithoutSchema{name: "moby", size: "large"})

      assert {:ok, ^written} = DiscWithoutSchemaStore.one(%{name: "moby"})
    end
  end

  describe "a valid mix of copy types" do
    setup do: create_existing(MixedCopies)

    test "runs the whole reconciliation instead of crashing the pipeline" do
      log =
        capture_log(fn ->
          assert Migration.migrate_table_options(MixedCopies) == :ok
        end)

      # the unreachable disc_only replica is refused and logged; the local
      # ram copy is untouched
      assert log =~ "could not add a disc_only_copies replica"
      assert :mnesia.table_info(MixedCopies, :ram_copies) == [node()]
    end
  end

  describe "the same node under two copy types" do
    test "raises, because the configuration is wrong on every boot" do
      assert_raise ArgumentError, ~r/under more than one copy type/, fn ->
        Migration.migrate_table_options(OverlappingCopies)
      end
    end
  end
end
