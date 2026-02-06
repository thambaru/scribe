defmodule SocialScribe.Integrations.Suggestions.SalesforceProvider do
  @moduledoc false

  @behaviour SocialScribe.Integrations.Suggestions.Provider

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

  @impl true
  def field_labels, do: @field_labels

  @impl true
  def get_contact(%UserCredential{} = credential, contact_id) do
    SalesforceApi.get_contact(credential, contact_id)
  end

  @impl true
  def ai_suggestions(meeting, contact) when is_map(contact) do
    AIContentGeneratorApi.generate_salesforce_suggestions(meeting, contact)
  end

  def ai_suggestions(_meeting, _contact), do: {:error, :missing_contact}

  @impl true
  def get_contact_field(contact, field) when is_map(contact) and is_binary(field) do
    key = Map.get(@field_to_key, field)
    if key, do: Map.get(contact, key), else: nil
  end

  def get_contact_field(_, _), do: nil
end

