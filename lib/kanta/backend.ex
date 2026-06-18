defmodule Kanta.Backend do
  @moduledoc """
  Kanta.Backend is a module that provides an enhanced Gettext backend with database support.

  It extends the standard Gettext functionality by:
  1. First checking for translations in the database
  2. Falling back to PO file translations if not found in the database

  ## Usage

  ```elixir
  defmodule MyApp.Gettext do
    use Kanta.Backend, otp_app: :my_app
  end
  ```

  ## Options

  * `:otp_app` - The OTP application that contains the backend
  * `:priv` - The directory where the translations are stored (defaults to "priv/YOUR_MODULE")
  * `:kanta_adapter` - The adapter module to use for database lookups (defaults to `Kanta.Backend.Adapter.CachedDB`)

  it also accepts all the Gettext.Backend options. See the official Gettext documentation for more details.


  """
  alias Kanta.Utils.ModuleFolder
  require Logger

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Logger
      @flag_file Path.join([Mix.Project.build_path(), "kanta_recompile", ".gettext_recompiled"])
      @adapter Keyword.get(opts, :kanta_adapter, Kanta.Backend.Adapter.CachedDB)
      opts = Keyword.drop(opts, [:kanta_adapter])
      # Generate fallback Gettext backend form PO files
      use Kanta.Backend.GettextFallback, opts

      # When `mix gettext extract` create POT/PO files based on this backend usage (ex. getext(...) call) across the application codebase.
      if Gettext.Extractor.extracting?() do
        use Gettext.Backend, opts

        Kanta.Utils.GettextRecompiler.setup_recompile_flag(@flag_file)
      else
        opts = Keyword.merge(opts, priv: "priv/#{ModuleFolder.safe_folder_name(__MODULE__)}")
        use Gettext.Backend, opts
      end

      def __mix_recompile__?() do
        Kanta.Utils.GettextRecompiler.needs_recompile?(@flag_file)
      end

      # `use Gettext.Backend` (above) defines `__gettext__/1` from a `@before_compile`
      # hook, so we register our own hook *after* it to override `:known_locales` — we
      # want the locales known to the PO-file fallback backend, not this backend's
      # (kanta-specific) priv dir. Doing this here in the module body instead would emit
      # an OTP 28+ "redundant clause" warning, because the generated clause would not
      # yet exist to be made overridable.
      @before_compile {Kanta.Backend, :__before_compile_known_locales__}

      def handle_missing_translation(locale, domain, msgctxt, msgid, bindings) do
        case Kanta.Backend.Adapter.CachedDB.lgettext(
               locale,
               domain,
               msgctxt,
               msgid,
               bindings
             ) do
          {:ok, translation} ->
            {:ok, translation}

          {:error, :not_found} ->
            backend = fallback_backend()
            backend.lgettext(locale, domain, msgctxt, msgid, bindings)
        end
      end

      def handle_missing_plural_translation(
            locale,
            domain,
            msgctxt,
            msgid,
            msgid_plural,
            n,
            bindings
          ) do
        case Kanta.Backend.Adapter.CachedDB.lngettext(
               locale,
               domain,
               msgctxt,
               msgid,
               msgid_plural,
               n,
               bindings
             ) do
          {:ok, translation} ->
            {:ok, translation}

          {:error, :not_found} ->
            backend = fallback_backend()

            backend.lngettext(
              locale,
              domain,
              msgctxt,
              msgid,
              msgid_plural,
              n,
              bindings
            )
        end
      end

      defp fallback_backend() do
        Module.concat(__MODULE__, GettextFallbackBackend)
      end
    end
  end

  @doc false
  defmacro __before_compile_known_locales__(_env) do
    quote do
      defoverridable __gettext__: 1

      # Resolve known locales from the PO-file fallback backend rather than this
      # backend's (kanta-specific) priv dir; delegate every other key to the
      # `use Gettext.Backend`-generated implementation via `super/1`.
      def __gettext__(:known_locales) do
        Gettext.known_locales(fallback_backend())
      end

      def __gettext__(key), do: super(key)
    end
  end
end
