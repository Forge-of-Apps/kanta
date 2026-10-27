defmodule Kanta.Cache do
  @moduledoc """
  Kanta Cache for minimalizing calls to DB.

  Every node keeps its own copy, filled from the database as it reads, and a
  deletion on any node drops the deleted entries on the others too: Nebulex's
  coherent topology, with only deletions sent across the cluster
  (`broadcast_partition/1`). A node filling its copy changes nothing the others
  hold, so a write that changes a translation deletes what it changes rather
  than overwriting it, or drops everything with `flush!/0`.
  """

  use Nebulex.Cache,
    otp_app: :kanta,
    adapter: Nebulex.Adapters.Coherent

  alias Nebulex.Event.CacheEntryEvent

  @impl true
  def init(config) do
    stream_opts = [partitions: 1, hash: &__MODULE__.broadcast_partition/1]
    {:ok, Keyword.update(config, :stream_opts, stream_opts, &Keyword.merge(&1, stream_opts))}
  end

  @doc """
  The partition of the cluster's event stream a cache event goes out on:
  deletions on the only one, every other event on none, so it stays on its node.
  """
  def broadcast_partition(%CacheEntryEvent{type: :deleted}), do: 0
  def broadcast_partition(%CacheEntryEvent{}), do: :none

  @doc """
  Drops every entry on every node. A deletion goes out to the other nodes only
  when it deletes something here, so the flush first keeps an entry to delete,
  whatever this node holds.
  """
  def flush! do
    put!({__MODULE__, :flush}, true)
    delete_all!()
  end

  def generate_cache_key(prefix, params) do
    Enum.reduce(params, prefix, fn {key, value}, acc ->
      case value do
        val when is_binary(val) ->
          acc <> "_" <> to_string(key) <> "_" <> URI.encode_query(val)

        val when is_list(val) ->
          # this old way is just broken for preloads lists
          # encoded_list = (Enum.into(val, %{}) |> URI.encode_query())
          # the new way is robust and reversible
          encoded_list =
            val
            |> :erlang.term_to_binary()
            |> URI.encode()
            |> then(&%{encoded_params: &1})
            |> URI.encode_query()

          acc <> "_" <> to_string(key) <> "_" <> encoded_list

        _val ->
          acc
      end
    end)
  end
end
