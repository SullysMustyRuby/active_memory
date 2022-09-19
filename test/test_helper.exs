Code.require_file("support/dogs/dog.ex", __DIR__)
Code.require_file("support/dogs/store.ex", __DIR__)
Code.require_file("support/people/person.ex", __DIR__)
Code.require_file("support/people/store.ex", __DIR__)
Code.require_file("support/whales/whale.ex", __DIR__)
Code.require_file("support/whales/store.ex", __DIR__)

# start the current node as a manager
:ok = LocalCluster.start()

# start your application tree manually
Application.ensure_all_started(:active_memory)

ExUnit.start(exclude: [:migration], max_cases: 1, seed: 0)
