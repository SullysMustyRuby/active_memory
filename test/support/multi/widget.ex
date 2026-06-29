defmodule Test.Support.Multi.Widget do
  use ActiveMemory.Table, type: :ets

  attributes do
    field(:name)
    field(:color)
  end
end
