defmodule Test.Support.People.Person do
  use ActiveMemory.Table, attributes: [:email, :first, :last, :hair_color, :age, :cylon?]
end
