defmodule ActiveMemory.Adapters.Ets.Migration do
end

# possible data migration
#  attributes(table, transform)
#  old = :ets.rename(table, name) 
#  new = :ets.new(table, [:named_table | options])
#  old
#  |> ets.tab2list()
#  |> Enum.each(fn record -> :ets.insert(new, transform(record)) end)

# options migraion
# options(table)
#  old = :ets.rename(table, name) 
#  new = :ets.new(table, [:named_table | options])
#  old
#  |> ets.tab2list()
#  |> Enum.each(fn record -> :ets.insert(new, transform(record)) end)

# tab2file(Table, Filename, Options) -> ok | {error, Reason}

# CoreProfile.Countries.Country

# path =
#   ~c[/Users/erinboeger/ElixirApps/ecomm/core_server/apps/core_profile/priv/repo/countries_test.txt]

# :ets.tab2file(CoreProfile.Countries.Country, path)
