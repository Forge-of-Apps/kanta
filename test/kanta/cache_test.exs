defmodule Kanta.CacheTest do
  use ExUnit.Case, async: false

  alias Kanta.Cache
  alias Nebulex.Event.CacheEntryEvent

  setup do
    Cache.Primary.subscribe!(partition: 0)
    :ok
  end

  defp elsewhere(fun), do: fun |> Task.async() |> Task.await()

  test "a node's fills and changes stay on it" do
    elsewhere(fn -> Cache.put!({__MODULE__, :filled}, "text") end)
    elsewhere(fn -> Cache.put!({__MODULE__, :filled}, "other text") end)

    refute_receive %CacheEntryEvent{}
  end

  test "a deletion goes out to the other nodes" do
    elsewhere(fn -> Cache.put!({__MODULE__, :deleted}, "text") end)
    elsewhere(fn -> Cache.delete!({__MODULE__, :deleted}) end)

    assert_receive %CacheEntryEvent{type: :deleted, target: {:key, {__MODULE__, :deleted}}}
    refute_receive %CacheEntryEvent{}
  end

  test "a flush goes out to the other nodes, even from a node holding nothing" do
    Cache.delete_all!()
    elsewhere(&Cache.flush!/0)

    assert_receive %CacheEntryEvent{type: :deleted, target: {:q, nil}}
    refute_receive %CacheEntryEvent{}
    assert Cache.count_all!() == 0
  end
end
