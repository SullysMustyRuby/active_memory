defmodule Test.Support.Multi.Gizmo do
  use ActiveMemory.Table, type: :ets

  attributes do
    field(:name)
  end
end
