# ActiveMemory

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mnesia_companion` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mnesia_companion, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mnesia_companion>.

Notes:
create a better query syntax.


- validations? -> Ecto style?
- Indexing 


agrigates?
sort

Setup options
  :mniesia
  :ets

  :mnesia, nodes: [node list]
  :mnesia, manager: true
  :ets heir -> MnesiaManager then when boots back gets back table? 




for u in User -> no we are not dealing with different tables, each repo has its own table

get(%{first: "name", last: "name"})

like? 
where :first == "name",
where :last == "name"

where :age > 12
{:>, :age, 12}

where :name == "erin" or :name == "tiberious"
{:or, {:==, :name, "erin"}, {:==, :name, "tiberious"}}

where :name == "erin" and :name == "tiberious"
{:and, {:==, :name, "erin"}, {:==, :name, "tiberious"}}

where :name == "erin" and :name == "tiberious" or :age < 35
{:or, {:and, {:==, :name, "erin"}, {:==, :name, "tiberious"}}, {:<, :age, 35}}

{:or, {:and, {:==, :name, "erin"}, {:==, :name, "tiberious"}}, {:<, :age, 35}}

where :name == "erin" and :age > 26
{:and, {:==, :name, "erin"}, {:>, :age, 26}}

{:and,
  {:>=, :year, 2010},
  {:or,
    {:==, :director, "Quentin Tarantino"},
    {:==, :director, "Steven Spielberg"},
  }
}
