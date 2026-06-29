defmodule Test.Support.Multi.InitRepo do
  use ActiveMemory.ActiveRepo,
    tables: [
      {Test.Support.Multi.Gizmo,
       seed_file: Path.expand("gizmo_seeds.exs", __DIR__), before_init: [{:warm, []}]}
    ],
    initial_state: {:custom_state, ["primary", "secondary"]}

  def warm do
    write(%Test.Support.Multi.Gizmo{name: "warmed"})
  end

  def custom_state(key, fallback) do
    {:ok, %{key: key, fallback: fallback}}
  end
end
