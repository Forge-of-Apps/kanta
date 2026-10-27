defmodule Kanta.Translations.SingularTranslations do
  @moduledoc """
  Singular translations Kanta subcontext
  """

  alias Kanta.Translations.SingularTranslations.Finders.{
    GetSingularTranslation,
    ListSingularTranslations
  }

  alias Kanta.Cache
  alias Kanta.Repo
  alias Kanta.Translations.SingularTranslation

  def list_singular_translations(params \\ []) do
    ListSingularTranslations.find(params)
  end

  def get_singular_translation(params \\ []) do
    GetSingularTranslation.find(params)
  end

  def create_singular_translation(attrs, opts \\ []) do
    attrs
    |> then(&SingularTranslation.changeset(%SingularTranslation{}, &1))
    |> Repo.get_repo().insert(opts)
    |> case do
      {:ok, singular_translation} ->
        # CachedDB caches each lookup's translated text under a key of its own
        # strings, which no single finder key here can reach, so drop the whole
        # cache, as create_message does. Translations are written by the PO
        # sync and dashboard actions only, never on the hot path.
        Cache.flush!()
        {:ok, singular_translation}

      error ->
        error
    end
  end

  def update_singular_translation(translation, attrs, opts \\ []) do
    SingularTranslation.changeset(translation, attrs)
    |> Repo.get_repo().update(opts)
    |> case do
      {:ok, translation} ->
        Cache.flush!()
        {:ok, translation}

      error ->
        error
    end
  end
end
