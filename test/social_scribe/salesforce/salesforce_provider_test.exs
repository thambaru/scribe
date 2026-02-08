defmodule SocialScribe.Integrations.Suggestions.SalesforceProviderTest do
  use ExUnit.Case, async: true

  alias SocialScribe.Integrations.Suggestions.SalesforceProvider

  describe "field_labels/0" do
    test "returns a map of 24 field labels" do
      labels = SalesforceProvider.field_labels()
      assert is_map(labels)
      assert map_size(labels) == 24
    end

    test "contains all core contact fields" do
      labels = SalesforceProvider.field_labels()

      assert labels["FirstName"] == "First Name"
      assert labels["LastName"] == "Last Name"
      assert labels["Email"] == "Email"
      assert labels["Phone"] == "Phone"
      assert labels["MobilePhone"] == "Mobile Phone"
      assert labels["Title"] == "Job Title"
      assert labels["Department"] == "Department"
    end

    test "contains mailing address fields" do
      labels = SalesforceProvider.field_labels()

      assert labels["MailingStreet"] == "Mailing Street"
      assert labels["MailingCity"] == "Mailing City"
      assert labels["MailingState"] == "Mailing State"
      assert labels["MailingPostalCode"] == "Mailing Postal Code"
      assert labels["MailingCountry"] == "Mailing Country"
    end

    test "contains other address fields" do
      labels = SalesforceProvider.field_labels()

      assert labels["OtherStreet"] == "Other Street"
      assert labels["OtherCity"] == "Other City"
      assert labels["OtherState"] == "Other State"
      assert labels["OtherPostalCode"] == "Other Postal Code"
      assert labels["OtherCountry"] == "Other Country"
    end

    test "contains assistant and misc fields" do
      labels = SalesforceProvider.field_labels()

      assert labels["AssistantName"] == "Assistant Name"
      assert labels["AssistantPhone"] == "Assistant Phone"
      assert labels["HomePhone"] == "Home Phone"
      assert labels["OtherPhone"] == "Other Phone"
      assert labels["Fax"] == "Fax"
      assert labels["Birthdate"] == "Birthdate"
      assert labels["Description"] == "Description"
    end
  end

  describe "get_contact_field/2" do
    test "maps FirstName to :firstname" do
      contact = %{firstname: "John"}
      assert SalesforceProvider.get_contact_field(contact, "FirstName") == "John"
    end

    test "maps LastName to :lastname" do
      contact = %{lastname: "Doe"}
      assert SalesforceProvider.get_contact_field(contact, "LastName") == "Doe"
    end

    test "maps Email to :email" do
      contact = %{email: "john@example.com"}
      assert SalesforceProvider.get_contact_field(contact, "Email") == "john@example.com"
    end

    test "maps Phone to :phone" do
      contact = %{phone: "555-1234"}
      assert SalesforceProvider.get_contact_field(contact, "Phone") == "555-1234"
    end

    test "maps MobilePhone to :mobilephone" do
      contact = %{mobilephone: "555-5678"}
      assert SalesforceProvider.get_contact_field(contact, "MobilePhone") == "555-5678"
    end

    test "maps Title to :title" do
      contact = %{title: "CTO"}
      assert SalesforceProvider.get_contact_field(contact, "Title") == "CTO"
    end

    test "maps Department to :department" do
      contact = %{department: "Engineering"}
      assert SalesforceProvider.get_contact_field(contact, "Department") == "Engineering"
    end

    test "maps MailingStreet to :mailing_street" do
      contact = %{mailing_street: "123 Main St"}
      assert SalesforceProvider.get_contact_field(contact, "MailingStreet") == "123 Main St"
    end

    test "maps MailingCity to :mailing_city" do
      contact = %{mailing_city: "San Francisco"}
      assert SalesforceProvider.get_contact_field(contact, "MailingCity") == "San Francisco"
    end

    test "maps MailingState to :mailing_state" do
      contact = %{mailing_state: "CA"}
      assert SalesforceProvider.get_contact_field(contact, "MailingState") == "CA"
    end

    test "maps MailingPostalCode to :mailing_postal_code" do
      contact = %{mailing_postal_code: "94102"}
      assert SalesforceProvider.get_contact_field(contact, "MailingPostalCode") == "94102"
    end

    test "maps MailingCountry to :mailing_country" do
      contact = %{mailing_country: "US"}
      assert SalesforceProvider.get_contact_field(contact, "MailingCountry") == "US"
    end

    test "maps HomePhone to :home_phone" do
      contact = %{home_phone: "555-HOME"}
      assert SalesforceProvider.get_contact_field(contact, "HomePhone") == "555-HOME"
    end

    test "maps OtherPhone to :other_phone" do
      contact = %{other_phone: "555-OTHER"}
      assert SalesforceProvider.get_contact_field(contact, "OtherPhone") == "555-OTHER"
    end

    test "maps Fax to :fax" do
      contact = %{fax: "555-FAX"}
      assert SalesforceProvider.get_contact_field(contact, "Fax") == "555-FAX"
    end

    test "maps AssistantName to :assistant_name" do
      contact = %{assistant_name: "Alice"}
      assert SalesforceProvider.get_contact_field(contact, "AssistantName") == "Alice"
    end

    test "maps AssistantPhone to :assistant_phone" do
      contact = %{assistant_phone: "555-ASST"}
      assert SalesforceProvider.get_contact_field(contact, "AssistantPhone") == "555-ASST"
    end

    test "maps OtherStreet to :other_street" do
      contact = %{other_street: "456 Side St"}
      assert SalesforceProvider.get_contact_field(contact, "OtherStreet") == "456 Side St"
    end

    test "maps OtherCity to :other_city" do
      contact = %{other_city: "Oakland"}
      assert SalesforceProvider.get_contact_field(contact, "OtherCity") == "Oakland"
    end

    test "maps OtherState to :other_state" do
      contact = %{other_state: "CA"}
      assert SalesforceProvider.get_contact_field(contact, "OtherState") == "CA"
    end

    test "maps OtherPostalCode to :other_postal_code" do
      contact = %{other_postal_code: "94612"}
      assert SalesforceProvider.get_contact_field(contact, "OtherPostalCode") == "94612"
    end

    test "maps OtherCountry to :other_country" do
      contact = %{other_country: "US"}
      assert SalesforceProvider.get_contact_field(contact, "OtherCountry") == "US"
    end

    test "maps Birthdate to :birthdate" do
      contact = %{birthdate: "1990-01-15"}
      assert SalesforceProvider.get_contact_field(contact, "Birthdate") == "1990-01-15"
    end

    test "maps Description to :description" do
      contact = %{description: "VIP contact"}
      assert SalesforceProvider.get_contact_field(contact, "Description") == "VIP contact"
    end

    test "returns nil for unknown field name" do
      contact = %{firstname: "John"}
      assert SalesforceProvider.get_contact_field(contact, "UnknownField") == nil
    end

    test "returns nil when contact does not have the mapped key" do
      contact = %{firstname: "John"}
      assert SalesforceProvider.get_contact_field(contact, "Phone") == nil
    end

    test "returns nil for non-map contact" do
      assert SalesforceProvider.get_contact_field(nil, "Phone") == nil
    end

    test "returns nil for non-binary field" do
      contact = %{phone: "555-1234"}
      assert SalesforceProvider.get_contact_field(contact, :phone) == nil
    end
  end

  describe "ai_suggestions/2" do
    test "returns error for non-map contact" do
      meeting = %{id: "meeting-1"}
      assert {:error, :missing_contact} = SalesforceProvider.ai_suggestions(meeting, nil)
    end

    test "returns error for list contact" do
      meeting = %{id: "meeting-1"}
      assert {:error, :missing_contact} = SalesforceProvider.ai_suggestions(meeting, [])
    end
  end
end
