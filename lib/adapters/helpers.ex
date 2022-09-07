defmodule ActiveMemory.Adapter.Helpers do
  @moduledoc false

  alias ActiveMemory.Adapters.{Ets, Mnesia}
  alias ActiveMemory.Adapters.Ets.Helpers, as: EtsHelpers
  alias ActiveMemory.Adapters.Mnesia.Helpers, as: MnesiaHelpers

  def build_match_head(query_map, _table_name, Ets) do
    EtsHelpers.build_match_head(query_map)
  end

  def build_match_head(query_map, table_name, Mnesia) do
    MnesiaHelpers.build_match_head(query_map, table_name)
  end

  def build_options(options, :ets), do: EtsHelpers.build_options(options)

  def build_options(options, :mnesia), do: MnesiaHelpers.build_options(options)

  def build_query_map(struct_attrs) do
    Enum.with_index(struct_attrs, fn element, index ->
      {strip_defaults(element), :"$#{index + 1}"}
    end)
  end

  def set_adapter(:ets), do: Ets

  def set_adapter(:mnesia), do: Mnesia

  defp strip_defaults(element) when is_atom(element), do: element

  defp strip_defaults({element, _defaults}) when is_atom(element), do: element
end
