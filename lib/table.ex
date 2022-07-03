defmodule ActiveMemory.Table do
  alias ActiveMemory.Definition

  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      opts = unquote(opts)

      @struct_attrs Keyword.get(opts, :attributes)
      @struct_keys Definition.build_struct_keys(@struct_attrs)
      @query_map Definition.build_query_map(@struct_attrs)
      @ets_match_head Definition.build_ets_match_head(@query_map, __MODULE__)
      @mnesia_match_head Definition.build_mnesia_match_head(@query_map, __MODULE__)

      defstruct @struct_attrs

      def __meta__,
        do: %{
          attributes: @struct_keys,
          query_map: @query_map,
          ets_match_head: @ets_match_head,
          mnesia_match_head: @mnesia_match_head
        }
    end
  end
end
