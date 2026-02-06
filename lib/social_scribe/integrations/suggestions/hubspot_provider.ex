defmodule SocialScribe.Integrations.Suggestions.HubspotProvider do
  @moduledoc false

  @behaviour SocialScribe.Integrations.Suggestions.Provider

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApi
  alias SocialScribe.Accounts.UserCredential

  @field_labels %{
    "firstname" => "First Name",
    "lastname" => "Last Name",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "Mobile Phone",
    "company" => "Company",
    "jobtitle" => "Job Title",
    "address" => "Address",
    "city" => "City",
    "state" => "State",
    "zip" => "ZIP Code",
    "country" => "Country",
    "website" => "Website",
    "linkedin_url" => "LinkedIn",
    "twitter_handle" => "Twitter"
  }

  @impl true
  def field_labels, do: @field_labels

  @impl true
  def get_contact(%UserCredential{} = credential, contact_id) do
    HubspotApi.get_contact(credential, contact_id)
  end

  @impl true
  def ai_suggestions(meeting, _contact) do
    AIContentGeneratorApi.generate_hubspot_suggestions(meeting)
  end

  @impl true
  def get_contact_field(contact, field) when is_map(contact) and is_binary(field) do
    field_atom = String.to_existing_atom(field)
    Map.get(contact, field_atom)
  rescue
    ArgumentError -> nil
  end

  def get_contact_field(_, _), do: nil
end

