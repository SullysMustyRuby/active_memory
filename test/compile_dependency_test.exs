defmodule ActiveMemory.CompileDependencyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # A `Store`/`ActiveRepo` must not inspect its table modules while it compiles.
  # Doing so makes every table a compile time dependency of its store, which
  # raises `UndefinedFunctionError` in any tool that compiles the store's file
  # without the table module loaded, such as a language server analyzing a
  # single file.
  defp compile(source) do
    capture_io(:stderr, fn -> Code.compile_string(source) end)
  end

  describe "a Store whose table module is not loaded" do
    test "compiles" do
      refute Code.ensure_loaded?(Unloaded.Table.Alpha)

      compile("""
      defmodule Unloaded.Store.Alpha do
        use ActiveMemory.Store, table: Unloaded.Table.Alpha
      end
      """)

      assert function_exported?(Unloaded.Store.Alpha, :start_link, 1)
    end

    test "compiles with a sweep_interval set" do
      compile("""
      defmodule Unloaded.Store.Beta do
        use ActiveMemory.Store, table: Unloaded.Table.Beta, sweep_interval: 50
      end
      """)

      assert function_exported?(Unloaded.Store.Beta, :start_link, 1)
    end
  end

  describe "an ActiveRepo whose table modules are not loaded" do
    test "compiles" do
      refute Code.ensure_loaded?(Unloaded.Table.Gamma)

      compile("""
      defmodule Unloaded.Repo.Gamma do
        use ActiveMemory.ActiveRepo, tables: [Unloaded.Table.Gamma, Unloaded.Table.Delta]
      end
      """)

      assert function_exported?(Unloaded.Repo.Gamma, :start_link, 1)
    end
  end
end
