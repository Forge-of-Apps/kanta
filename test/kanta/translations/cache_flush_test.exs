defmodule Kanta.Translations.CacheFlushTest do
  @moduledoc """
  A write to a locale or an application source drops what the cache kept of it,
  as translation and message writes do, so the next read sees the write.
  """
  use Kanta.Test.DataCase, async: false

  alias Kanta.Cache
  alias Kanta.Translations

  setup do
    Cache.delete_all!()
    :ok
  end

  test "updating a locale drops the cached locale" do
    {:ok, locale} =
      Translations.create_locale(%{
        native_name: "Français",
        name: "French",
        iso639_code: "fr",
        plurals_header: "nplurals=2; plural=(n > 1);"
      })

    assert {:ok, %{plurals_header: "nplurals=2; plural=(n > 1);"}} =
             Translations.get_locale(filter: [iso639_code: "fr"])

    {:ok, _locale} =
      Translations.update_locale(locale, %{plurals_header: "nplurals=1; plural=0;"})

    assert {:ok, %{plurals_header: "nplurals=1; plural=0;"}} =
             Translations.get_locale(filter: [iso639_code: "fr"])
  end

  test "updating an application source drops the cached application source" do
    {:ok, source} = Translations.create_application_source(%{name: "web"})

    assert {:ok, %{description: nil}} =
             Translations.get_application_source(filter: [id: source.id])

    {:ok, _source} = Translations.update_application_source(source, %{description: "The site"})

    assert {:ok, %{description: "The site"}} =
             Translations.get_application_source(filter: [id: source.id])
  end
end
