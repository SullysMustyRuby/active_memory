defmodule Test.Support.People.Person do
  use ActiveMemory.Table,
    options: [index: [:last, :cylon?]]

  attributes do
    field(:email, :string)
    field(:first, :string)
    field(:last, :string)
    field(:hair_color, :string)
    field(:age, :integer)
    field(:cylon?, :boolean)
  end
end
