defmodule Test.Support.Whales.Whale do
  use ActiveMemory.Table,
    options: [index: [:first, :last, :email]]

  attributes do
    field(:email)
    field(:first)
    field(:last)
    field(:hair_color)
    field(:age)
  end
end
