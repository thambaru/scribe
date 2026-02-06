defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens.
  """

  @salesforce_token_url "https://login.salesforce.com/services/oauth2/token"

  def client do
    Tesla.client([
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end

  @doc """
  Refreshes a Salesforce access token using the refresh token.
  Returns {:ok, response_body} with new access_token and other token info.
  Note: Salesforce may not return a new refresh_token - the original one remains valid.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    case Tesla.post(client(), @salesforce_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a Salesforce credential and updates it in the database.
  """
  def refresh_credential(credential) do
    alias SocialScribe.Accounts

    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
        # Salesforce tokens typically expire in 2 hours (7200 seconds)
        # But we calculate from issued_at if provided, or assume 2 hours
        expires_in = response["issued_at"]
        expires_at = if expires_in do
          # issued_at is in milliseconds since epoch
          issued_at_ms = String.to_integer(expires_in)
          issued_at = DateTime.from_unix!(div(issued_at_ms, 1000))
          # Add 2 hours (standard Salesforce token lifetime)
          DateTime.add(issued_at, 7200, :second)
        else
          DateTime.add(DateTime.utc_now(), 7200, :second)
        end

        # Salesforce may return a new instance_url
        new_instance_url = response["instance_url"]
        current_metadata = credential.metadata || %{}
        updated_metadata = if new_instance_url do
          Map.put(current_metadata, "instance_url", new_instance_url)
        else
          current_metadata
        end

        attrs = %{
          token: response["access_token"],
          # Salesforce doesn't always return a new refresh_token, keep the old one
          refresh_token: response["refresh_token"] || credential.refresh_token,
          expires_at: expires_at,
          metadata: updated_metadata
        }

        Accounts.update_user_credential(credential, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300

    if DateTime.compare(
         credential.expires_at,
         DateTime.add(DateTime.utc_now(), buffer_seconds, :second)
       ) == :lt do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end
end
