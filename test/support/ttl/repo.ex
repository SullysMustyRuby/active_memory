defmodule Test.Support.Ttl.Repo do
  use ActiveMemory.ActiveRepo,
    tables: [Test.Support.Ttl.Session],
    sweep_interval: 300
end
