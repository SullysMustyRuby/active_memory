defmodule Test.Support.Ttl.TokenStore do
  use ActiveMemory.Store,
    table: Test.Support.Ttl.Token,
    sweep_interval: 300
end
