defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes Salesforce OAuth tokens before they expire.
  Runs every 5 minutes and refreshes tokens expiring within 10 minutes.
  """

  alias SocialScribe.SalesforceTokenRefresher

  use SocialScribe.Workers.ProactiveOAuthTokenRefresher,
    provider: "salesforce",
    refresher: SalesforceTokenRefresher,
    label: "Salesforce"
end
