defmodule ActiveMemory.Table do
  alias ActiveMemory.Definition

  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      opts = unquote(opts)

      @table_attrs Keyword.get(opts, :attributes)
      @query_map Definition.build_query_map(@table_attrs)
      @match_head Definition.build_match_head(@query_map)

      defstruct @table_attrs

      def __meta__,
        do: %{attributes: @table_attrs, query_map: @query_map, match_head: @match_head}
    end
  end
end
