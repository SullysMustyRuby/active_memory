defmodule Test.Support.People.Person do
  use Memento.Table, attributes: [:email, :first, :last, :hair_color, :age, :cylon?]

  def new(attributes) do
    %__MODULE__{}
    |> Map.merge(attributes)
  end
end
