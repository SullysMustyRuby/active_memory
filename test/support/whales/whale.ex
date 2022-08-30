defmodule Test.Support.Whales.Whale do
  use ActiveMemory.Table.Attributes,
    options: [index: [:first, :last, :email]]

  attributes "whales" do
    field(:email, :string)
    field(:first, :string)
    field(:last, :string)
    field(:hair_color, :string)
    field(:age, :integer)
  end
end
