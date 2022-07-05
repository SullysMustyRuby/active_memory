defmodule ActiveMemory.Table do
  @moduledoc """
  Define your table attributes and defaults just like a regular Elixir module struct.
  Keys can have defaults defined.
  `ActiveMemory.Table` are `:ets` and `:mneisia` agnostic and thus allows you to change your `ActiveMemory.Store` type without having to change your table.


  Example Table:
  ```elixir
  defmodule MyApp.People.Person do
  use ActiveMemory.Table attributes: [
    :uuid, 
    :email, 
    :first_name,
    :last_name,
    :department,
    :start_date,
    :active,
    :admin?
    complex: %{more: "complex", keys: "can be used", with: "defaults"}
  ]
  end
  ```
  """
  alias ActiveMemory.Adapter.Helpers

  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)

      opts = unquote(Macro.expand(opts, __CALLER__))

      @struct_attrs Keyword.get(opts, :attributes)
      @table_type Keyword.get(opts, :type, :mnesia)
      @adapter Helpers.set_adapter(@table_type)
      @query_map Helpers.build_query_map(@struct_attrs)
      @table_options Keyword.get(opts, :options, :defaults)

      defstruct @struct_attrs

      def __meta__,
        do: %{
          adapter: @adapter,
          attributes: Helpers.build_struct_keys(@struct_attrs),
          match_head: Helpers.build_match_head(@query_map, __MODULE__, @table_type),
          query_map: @query_map,
          table_options: Helpers.build_options(@table_options, @table_type)
        }

      def adapter, do: @adapter
    end
  end
end
