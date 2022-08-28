defmodule Test.Support.Whales.Whale do
  # use ActiveMemory.Table,
  #   options: [index: [:first, :last, :email]]

  use ActiveMemory.Table.Attributes

  attributes "whales" do
    field(:email, :string)
    field(:first, :string)
    field(:last, :string)
    field(:hair_color, :string)
    field(:age, :integer)
  end
end
