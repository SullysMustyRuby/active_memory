defmodule Test.Support.Multi.Repo do
  use ActiveMemory.ActiveRepo,
    tables: [
      {Test.Support.Multi.Widget,
       seed_file: Path.expand("widget_seeds.exs", __DIR__), before_init: [{:warm, []}]},
      Test.Support.Multi.Gadget
    ]

  def warm do
    write(%Test.Support.Multi.Widget{name: "warmed", color: "blue"})
  end
end
