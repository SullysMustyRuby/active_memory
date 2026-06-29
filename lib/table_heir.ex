defmodule ActiveMemory.TableHeir do
  @moduledoc """
  Stable "owner of last resort" for the ETS tables created by `ActiveMemory.Store`.

  Each ETS table is created with this process set as its ETS `:heir`. When a
  store process terminates, ETS transfers the table to this process instead of
  destroying it, preserving the data. When the store restarts it reclaims the
  table via `claim/1`, so ETS data survives store crashes and restarts.

  This process is started automatically by `ActiveMemory.Application`; no changes
  to a host application's supervision tree and no changes to the `Store` API are
  required. When the heir is not running, stores fall back to the previous
  behaviour of creating a fresh table.
  """

  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Reclaim ownership of `table` for the calling process.

  Returns `:ok` when the heir is currently holding `table` and has handed it back
  to the caller, or `{:error, :not_held}` when the heir is not the table's owner
  (the table does not exist, or it is owned by another process).

      iex> ActiveMemory.TableHeir.claim(:a_table_the_heir_does_not_hold)
      {:error, :not_held}
  """
  @spec claim(atom()) :: :ok | {:error, :not_held}
  def claim(table) do
    GenServer.call(@name, {:claim, table, self()})
  end

  @doc """
  Return the pid of the running heir, or `nil` when it is not started.
  """
  @spec whereis() :: pid() | nil
  def whereis, do: Process.whereis(@name)

  @impl true
  def init(_opts), do: {:ok, MapSet.new()}

  @impl true
  def handle_call({:claim, table, pid}, _from, held_tables) do
    case held?(table) do
      true ->
        :ets.give_away(table, pid, table)
        {:reply, :ok, MapSet.delete(held_tables, table)}

      false ->
        {:reply, {:error, :not_held}, held_tables}
    end
  end

  @impl true
  def handle_info({:"ETS-TRANSFER", _table_ref, _from, table}, held_tables) do
    {:noreply, MapSet.put(held_tables, table)}
  end

  def handle_info(_message, held_tables), do: {:noreply, held_tables}

  defp held?(table) do
    case :ets.whereis(table) do
      :undefined -> false
      _table_ref -> :ets.info(table, :owner) == self()
    end
  end
end
