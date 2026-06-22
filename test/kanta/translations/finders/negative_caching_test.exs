defmodule Kanta.Translations.Finders.NegativeCachingTest do
  @moduledoc """
  Covers the caching contract shared by the GetMessage / GetSingularTranslation /
  GetPluralTranslation finders' `find/1`:

    * a database hit caches the struct and returns `{:ok, struct}`
    * a database miss negative-caches the `:not_found` sentinel and returns
      `{:error, name, :not_found}`
    * a cache hit (struct *or* `:not_found`) short-circuits the database
  """
  use Kanta.Test.DataCase, async: false

  alias Kanta.Cache
  alias Kanta.Translations

  alias Kanta.Translations.{Message, PluralTranslation, SingularTranslation}

  alias Kanta.Translations.Messages.Finders.GetMessage
  alias Kanta.Translations.PluralTranslations.Finders.GetPluralTranslation
  alias Kanta.Translations.SingularTranslations.Finders.GetSingularTranslation

  setup do
    Cache.delete_all()

    {:ok, locale} =
      Translations.create_locale(%{
        native_name: "Français",
        name: "French",
        iso639_code: "fr",
        plurals_header: "nplurals=2; plural=(n > 1);"
      })

    {:ok, domain} = Translations.create_domain(%{name: "test_domain"})
    {:ok, context} = Translations.create_context(%{name: "test_context"})

    {:ok, singular_message} =
      Translations.create_message(%{
        message_type: :singular,
        msgid: "Hello world",
        context_id: context.id,
        domain_id: domain.id
      })

    {:ok, plural_message} =
      Translations.create_message(%{
        message_type: :plural,
        msgid: "%{count} items",
        context_id: context.id,
        domain_id: domain.id
      })

    {:ok, singular_translation} =
      Translations.create_singular_translation(%{
        locale_id: locale.id,
        message_id: singular_message.id,
        translated_text: "Bonjour le monde"
      })

    {:ok, plural_translation} =
      Translations.create_plural_translation(%{
        locale_id: locale.id,
        message_id: plural_message.id,
        nplural_index: 0,
        translated_text: "%{count} élément"
      })

    # create_message / create_*_translation warm the cache; start each test cold.
    Cache.delete_all()

    {:ok,
     %{
       message: singular_message,
       singular_translation: singular_translation,
       plural_translation: plural_translation
     }}
  end

  describe "GetMessage.find/1" do
    test "database hit returns the struct and caches it", %{message: message} do
      params = [filter: [id: message.id]]
      key = Cache.generate_cache_key("message", params)

      assert is_nil(Cache.get(key))
      assert {:ok, %Message{id: id}} = GetMessage.find(params)
      assert id == message.id
      assert %Message{id: ^id} = Cache.get(key)
    end

    test "database miss returns :not_found and negative-caches the sentinel" do
      params = [filter: [id: -1]]
      key = Cache.generate_cache_key("message", params)

      assert {:error, :message, :not_found} = GetMessage.find(params)
      assert Cache.get(key) == :not_found
    end

    # The two cache-hit tests below exercise the `{:ok, cached} -> cached` else
    # clause, which is identical and literal-free across all three finders, so
    # they live only here rather than being triplicated.
    test "cached struct is returned without touching the database" do
      # id has no row in the DB, but a struct is cached under its key.
      params = [filter: [id: -1]]
      key = Cache.generate_cache_key("message", params)
      cached = %Message{id: 123, msgid: "cached"}
      Cache.put(key, cached)

      assert {:ok, ^cached} = GetMessage.find(params)
    end

    test "cached :not_found short-circuits an existing row", %{message: message} do
      params = [filter: [id: message.id]]
      key = Cache.generate_cache_key("message", params)
      Cache.put(key, :not_found)

      assert {:error, :message, :not_found} = GetMessage.find(params)
    end
  end

  describe "GetSingularTranslation.find/1" do
    test "database hit returns the struct and caches it", %{singular_translation: translation} do
      params = [filter: [id: translation.id]]
      key = Cache.generate_cache_key("singular_translation", params)

      assert is_nil(Cache.get(key))
      assert {:ok, %SingularTranslation{id: id}} = GetSingularTranslation.find(params)
      assert id == translation.id
      assert %SingularTranslation{id: ^id} = Cache.get(key)
    end

    test "database miss returns :not_found and negative-caches the sentinel" do
      params = [filter: [id: -1]]
      key = Cache.generate_cache_key("singular_translation", params)

      assert {:error, :singular_translation, :not_found} = GetSingularTranslation.find(params)
      assert Cache.get(key) == :not_found
    end
  end

  describe "GetPluralTranslation.find/1" do
    test "database hit returns the struct and caches it", %{plural_translation: translation} do
      params = [filter: [id: translation.id]]
      key = Cache.generate_cache_key("plural_translation", params)

      assert is_nil(Cache.get(key))
      assert {:ok, %PluralTranslation{id: id}} = GetPluralTranslation.find(params)
      assert id == translation.id
      assert %PluralTranslation{id: ^id} = Cache.get(key)
    end

    test "database miss returns :not_found and negative-caches the sentinel" do
      params = [filter: [id: -1]]
      key = Cache.generate_cache_key("plural_translation", params)

      assert {:error, :plural_translation, :not_found} = GetPluralTranslation.find(params)
      assert Cache.get(key) == :not_found
    end
  end

  setup_all do
    on_exit(fn -> Cache.delete_all() end)
  end
end
