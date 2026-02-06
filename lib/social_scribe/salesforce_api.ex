defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v59.0"

  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "Department",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "Account.Name"
  ]

  defp client(access_token, instance_url) do
    base_url = "#{instance_url}/services/data/#{@api_version}"

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  defp get_instance_url(%UserCredential{metadata: metadata}) when is_map(metadata) do
    metadata["instance_url"]
  end

  defp get_instance_url(_), do: nil

  @doc """
  Searches for contacts using Salesforce SOSL.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)

      if is_nil(instance_url) do
        {:error, :missing_instance_url}
      else
        # Escape special SOSL characters
        escaped_query = escape_sosl_query(query)
        fields = Enum.join(@contact_fields, ", ")

        # SOSL search query
        sosl_query =
          "FIND {#{escaped_query}} IN ALL FIELDS RETURNING Contact(#{fields}) LIMIT 10"

        encoded_query = URI.encode(sosl_query)
        url = "/search/?q=#{encoded_query}"

        case Tesla.get(client(cred.token, instance_url), url) do
          {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => results}}} ->
            contacts = Enum.map(results, &format_contact/1)
            {:ok, contacts}

          {:ok, %Tesla.Env{status: 200, body: body}} when is_list(body) ->
            # Alternative response format
            contacts = Enum.map(body, &format_contact/1)
            {:ok, contacts}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Gets a single contact by ID with all properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)

      if is_nil(instance_url) do
        {:error, :missing_instance_url}
      else
        fields = Enum.join(@contact_fields, ",")
        url = "/sobjects/Contact/#{contact_id}?fields=#{fields}"

        case Tesla.get(client(cred.token, instance_url), url) do
          {:ok, %Tesla.Env{status: 200, body: body}} ->
            {:ok, format_contact(body)}

          {:ok, %Tesla.Env{status: 404, body: _body}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of Salesforce field names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      instance_url = get_instance_url(cred)

      if is_nil(instance_url) do
        {:error, :missing_instance_url}
      else
        url = "/sobjects/Contact/#{contact_id}"

        case Tesla.patch(client(cred.token, instance_url), url, updates) do
          {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
            # Salesforce returns 204 No Content on successful PATCH
            # Fetch the updated contact to return it
            get_contact(credential, contact_id)

          {:ok, %Tesla.Env{status: 404, body: _body}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = contact) do
    # Handle nested Account.Name
    account_name =
      case contact do
        %{"Account" => %{"Name" => name}} -> name
        _ -> nil
      end

    %{
      id: id,
      firstname: contact["FirstName"],
      lastname: contact["LastName"],
      email: contact["Email"],
      phone: contact["Phone"],
      mobilephone: contact["MobilePhone"],
      title: contact["Title"],
      department: contact["Department"],
      mailing_street: contact["MailingStreet"],
      mailing_city: contact["MailingCity"],
      mailing_state: contact["MailingState"],
      mailing_postal_code: contact["MailingPostalCode"],
      mailing_country: contact["MailingCountry"],
      company: account_name,
      display_name: format_display_name(contact)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(contact) do
    firstname = contact["FirstName"] || ""
    lastname = contact["LastName"] || ""
    email = contact["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Escape special characters for SOSL queries
  defp escape_sosl_query(query) do
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
    |> String.replace("?", "\\?")
    |> String.replace("&", "\\&")
    |> String.replace("|", "\\|")
    |> String.replace("!", "\\!")
    |> String.replace("{", "\\{")
    |> String.replace("}", "\\}")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace("^", "\\^")
    |> String.replace("~", "\\~")
    |> String.replace("*", "\\*")
    |> String.replace(":", "\\:")
  end

  # Wrapper that handles token refresh on auth errors
  # Tries the API call, and if it fails with 401, refreshes token and retries once
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, 401, body}} ->
          Logger.info("Salesforce token expired, refreshing and retrying...")
          retry_with_fresh_token(credential, api_call)

        {:error, {:api_error, status, body}} when status in [400, 403] ->
          if is_token_error?(body) do
            Logger.info("Salesforce token error, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(body) when is_list(body) do
    Enum.any?(body, fn
      %{"errorCode" => code} -> code in ["INVALID_SESSION_ID", "INVALID_AUTH_HEADER"]
      %{"error" => error} -> error in ["invalid_grant", "invalid_token"]
      _ -> false
    end)
  end

  defp is_token_error?(%{"error" => error}) do
    error in ["invalid_grant", "invalid_token", "expired_token"]
  end

  defp is_token_error?(_), do: false
end
