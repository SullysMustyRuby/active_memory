defmodule Test.Support.Whales.Whale do
  use ActiveMemory.Table,
    options: [index: [:first, :last], ram_copies: [:"app_instance1@127.0.0.1"]]

  attributes do
    field(:email)
    field(:first)
    field(:last)
    field(:hair_color)
    field(:age)
  end
end
