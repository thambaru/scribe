defmodule SocialScribe.Workers.HubspotTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes HubSpot OAuth tokens before they expire.
  Runs every 5 minutes and refreshes tokens expiring within 10 minutes.
  """

  alias SocialScribe.HubspotTokenRefresher

  use SocialScribe.Workers.ProactiveOAuthTokenRefresher,
    provider: "hubspot",
    refresher: HubspotTokenRefresher,
    label: "HubSpot"
end
