defmodule Test.Support.People.Person do
  use ActiveMemory.Table,
    options: [index: [:last, :cylon?]]

  attributes do
    field(:email)
    field(:first)
    field(:last)
    field(:hair_color)
    field(:age)
    field(:cylon?)
  end
end
