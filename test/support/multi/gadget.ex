defmodule Test.Support.Multi.Gadget do
  use ActiveMemory.Table,
    options: [index: [:category]]

  attributes auto_generate_uuid: true do
    field(:name)
    field(:category)
  end
end
