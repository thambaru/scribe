defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "Department",
          label: "Department",
          current_value: nil,
          new_value: "Engineering",
          context: "Works in Engineering",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XX0000012345",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        mobilephone: nil,
        title: nil,
        department: "Engineering",
        mailing_street: nil,
        mailing_city: nil,
        mailing_state: nil,
        mailing_postal_code: nil,
        mailing_country: nil,
        company: nil,
        display_name: "John Doe"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(result) == 1
      assert hd(result).field == "Phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "Email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XX0000012345",
        firstname: "Test",
        lastname: "User",
        email: "test@example.com",
        phone: nil,
        mobilephone: nil,
        title: nil,
        department: nil,
        mailing_street: nil,
        mailing_city: nil,
        mailing_state: nil,
        mailing_postal_code: nil,
        mailing_country: nil,
        company: nil,
        display_name: "Test User"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{
        id: "003XX0000012345",
        firstname: "Test",
        lastname: "User",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact([], contact)
      assert result == []
    end

    test "sets apply to true and has_change to true for changed fields" do
      suggestions = [
        %{
          field: "Title",
          label: "Job Title",
          current_value: nil,
          new_value: "CTO",
          context: "Mentioned as CTO",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XX0000012345",
        firstname: "Jane",
        lastname: "Smith",
        email: "jane@example.com",
        phone: nil,
        mobilephone: nil,
        title: nil,
        department: nil,
        mailing_street: nil,
        mailing_city: nil,
        mailing_state: nil,
        mailing_postal_code: nil,
        mailing_country: nil,
        company: nil,
        display_name: "Jane Smith"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert length(result) == 1
      suggestion = hd(result)
      assert suggestion.apply == true
      assert suggestion.has_change == true
      assert suggestion.new_value == "CTO"
    end

    test "populates current_value from contact data" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-9999",
          context: "New phone",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XX0000012345",
        firstname: "Test",
        lastname: "User",
        email: "test@example.com",
        phone: "555-0000",
        mobilephone: nil,
        title: nil,
        department: nil,
        mailing_street: nil,
        mailing_city: nil,
        mailing_state: nil,
        mailing_postal_code: nil,
        mailing_country: nil,
        company: nil,
        display_name: "Test User"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert length(result) == 1
      assert hd(result).current_value == "555-0000"
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XX0000012345",
        phone: nil,
        mobilephone: nil,
        firstname: nil,
        lastname: nil,
        email: nil,
        title: nil,
        department: nil,
        mailing_street: nil,
        mailing_city: nil,
        mailing_state: nil,
        mailing_postal_code: nil,
        mailing_country: nil,
        company: nil,
        display_name: ""
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert hd(result).label == "Phone"
    end
  end
end
