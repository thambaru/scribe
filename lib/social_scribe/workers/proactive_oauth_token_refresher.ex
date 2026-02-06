defmodule SocialScribe.Workers.ProactiveOAuthTokenRefresher do
  @moduledoc false

  # Shared logic for the provider-specific Oban refresh workers.
  #
  # Keeps the existing `SocialScribe.Workers.HubspotTokenRefresher` and
  # `SocialScribe.Workers.SalesforceTokenRefresher` modules intact as wrappers,
  # while deduplicating the batch refresh logic.

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    refresher = Keyword.fetch!(opts, :refresher)
    label = Keyword.get(opts, :label, provider)
    refresh_threshold_minutes = Keyword.get(opts, :refresh_threshold_minutes, 10)

    quote do
      use Oban.Worker, queue: :default, max_attempts: 3

      alias SocialScribe.Repo
      alias SocialScribe.Accounts.UserCredential

      import Ecto.Query

      require Logger

      @refresh_threshold_minutes unquote(refresh_threshold_minutes)
      @provider unquote(provider)
      @refresher unquote(refresher)
      @label unquote(label)

      @impl Oban.Worker
      def perform(_job) do
        Logger.info("Running proactive #{@label} token refresh check...")

        expiring_credentials = get_expiring_credentials()

        case expiring_credentials do
          [] ->
            Logger.debug("No #{@label} tokens expiring soon")
            :ok

          credentials ->
            Logger.info(
              "Found #{length(credentials)} #{@label} token(s) expiring soon, refreshing..."
            )

            refresh_all(credentials)
        end
      end

      defp get_expiring_credentials do
        threshold = DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes, :minute)

        from(c in UserCredential,
          where: c.provider == ^@provider,
          where: c.expires_at < ^threshold,
          where: not is_nil(c.refresh_token)
        )
        |> Repo.all()
      end

      defp refresh_all(credentials) do
        results =
          Enum.map(credentials, fn credential ->
            case @refresher.refresh_credential(credential) do
              {:ok, _updated} ->
                Logger.info("Proactively refreshed #{@label} token for credential #{credential.id}")
                :ok

              {:error, reason} ->
                Logger.error(
                  "Failed to proactively refresh #{@label} token for credential #{credential.id}: #{inspect(reason)}"
                )

                {:error, credential.id, reason}
            end
          end)

        _errors = Enum.filter(results, &match?({:error, _, _}, &1))

        # Return ok anyway; we do not want to retry the whole batch.
        :ok
      end
    end
  end
end

