defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates and formats Salesforce contact update suggestions by combining
  AI-extracted data with existing Salesforce contact information.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.SalesforceApi
  alias SocialScribe.Accounts.UserCredential

  @field_labels %{
    "FirstName" => "First Name",
    "LastName" => "Last Name",
    "Email" => "Email",
    "Phone" => "Phone",
    "MobilePhone" => "Mobile Phone",
    "Title" => "Job Title",
    "Department" => "Department",
    "MailingStreet" => "Street Address",
    "MailingCity" => "City",
    "MailingState" => "State",
    "MailingPostalCode" => "Postal Code",
    "MailingCountry" => "Country"
  }

  # Map from Salesforce field names to our internal contact map keys
  @field_to_key %{
    "FirstName" => :firstname,
    "LastName" => :lastname,
    "Email" => :email,
    "Phone" => :phone,
    "MobilePhone" => :mobilephone,
    "Title" => :title,
    "Department" => :department,
    "MailingStreet" => :mailing_street,
    "MailingCity" => :mailing_city,
    "MailingState" => :mailing_state,
    "MailingPostalCode" => :mailing_postal_code,
    "MailingCountry" => :mailing_country
  }

  @doc """
  Generates suggested updates for a Salesforce contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the Salesforce field name
  - label: human-readable field label
  - current_value: the existing value in Salesforce (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default true)
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- SalesforceApi.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_salesforce_suggestions(meeting, contact) do
      suggestions =
        ai_suggestions
        |> Enum.map(fn suggestion ->
          field = suggestion.field
          current_value = get_contact_field(contact, field)

          %{
            field: field,
            label: Map.get(@field_labels, field, field),
            current_value: current_value,
            new_value: suggestion.value,
            context: suggestion.context,
            timestamp: suggestion.timestamp,
            apply: true,
            has_change: current_value != suggestion.value
          }
        end)
        |> Enum.filter(fn s -> s.has_change end)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions for a specific contact without re-fetching from Salesforce.
  Useful when contact data is already available.
  """
  def generate_suggestions_from_meeting(meeting, contact) do
    case AIContentGeneratorApi.generate_salesforce_suggestions(meeting, contact) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    Enum.map(suggestions, fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)

      %{suggestion | current_value: current_value, has_change: current_value != suggestion.new_value, apply: true}
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  defp get_contact_field(contact, field) when is_map(contact) do
    # Map Salesforce field name to our internal contact map key
    key = Map.get(@field_to_key, field)

    if key do
      Map.get(contact, key)
    else
      nil
    end
  end

  defp get_contact_field(_, _), do: nil
end
