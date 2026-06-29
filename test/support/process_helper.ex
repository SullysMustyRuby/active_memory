defmodule Test.Support.ProcessHelper do
  @moduledoc """
  Test helpers for deterministically stopping named processes.

  The stores are named `GenServer`s, so a test that calls `start_link` while a
  previous instance is still shutting down gets `{:error, {:already_started, pid}}`.
  Calling `stop/1` before `start_link` (or in teardown) removes that race by waiting
  for the process to actually terminate and free its registered name.
  """

  @stop_timeout 2_000

  @doc """
  Synchronously and gracefully stop `server` (a registered name or pid), returning
  only after it has terminated. A no-op when nothing is running under `server`.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    case GenServer.whereis(server) do
      nil ->
        :ok

      pid ->
        try do
          GenServer.stop(pid, :normal, @stop_timeout)
        catch
          :exit, _reason -> :ok
        end
    end
  end
end
