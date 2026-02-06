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
    "HomePhone" => "Home Phone",
    "MobilePhone" => "Mobile Phone",
    "OtherPhone" => "Other Phone",
    "Fax" => "Fax",
    "Title" => "Job Title",
    "Department" => "Department",
    "AssistantName" => "Assistant Name",
    "AssistantPhone" => "Assistant Phone",
    "MailingStreet" => "Mailing Street",
    "MailingCity" => "Mailing City",
    "MailingState" => "Mailing State",
    "MailingPostalCode" => "Mailing Postal Code",
    "MailingCountry" => "Mailing Country",
    "OtherStreet" => "Other Street",
    "OtherCity" => "Other City",
    "OtherState" => "Other State",
    "OtherPostalCode" => "Other Postal Code",
    "OtherCountry" => "Other Country",
    "Birthdate" => "Birthdate",
    "Description" => "Description"
  }

  @field_to_key %{
    "FirstName" => :firstname,
    "LastName" => :lastname,
    "Email" => :email,
    "Phone" => :phone,
    "HomePhone" => :home_phone,
    "MobilePhone" => :mobilephone,
    "OtherPhone" => :other_phone,
    "Fax" => :fax,
    "Title" => :title,
    "Department" => :department,
    "AssistantName" => :assistant_name,
    "AssistantPhone" => :assistant_phone,
    "MailingStreet" => :mailing_street,
    "MailingCity" => :mailing_city,
    "MailingState" => :mailing_state,
    "MailingPostalCode" => :mailing_postal_code,
    "MailingCountry" => :mailing_country,
    "OtherStreet" => :other_street,
    "OtherCity" => :other_city,
    "OtherState" => :other_state,
    "OtherPostalCode" => :other_postal_code,
    "OtherCountry" => :other_country,
    "Birthdate" => :birthdate,
    "Description" => :description
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
