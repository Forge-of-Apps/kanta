defmodule Kanta.Cache do
  @moduledoc """
  Kanta Cache for minimalizing calls to DB.

  A Nebulex cache partitioned across the nodes of a cluster. An application that
  serves translations from a single node can make it a local cache at compile time,
  which answers a read without routing its key through the cluster's hash ring,
  about a third of the cost of each of the reads behind every gettext call:

      config :kanta, :cache_adapter, Nebulex.Adapters.Local

  A local cache drops entries on its own node only, so keep the partitioned
  default wherever several nodes serve translations.
  """

  @cache_adapter Application.compile_env(:kanta, :cache_adapter, Nebulex.Adapters.Partitioned)

  use Nebulex.Cache,
    otp_app: :kanta,
    adapter: @cache_adapter,
    adapter_opts:
      if(@cache_adapter == Nebulex.Adapters.Partitioned,
        do: [primary_storage_adapter: Nebulex.Adapters.Local],
        else: []
      )

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
