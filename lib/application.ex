defmodule ActiveMemory.Application do
  @moduledoc """
  Starts the `ActiveMemory` supervision tree, which runs the
  `ActiveMemory.TableHeir` process that preserves ETS tables across store
  crashes and restarts.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ActiveMemory.TableHeir
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ActiveMemory.Supervisor)
  end
end
