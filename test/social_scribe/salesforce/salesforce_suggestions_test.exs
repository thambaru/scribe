defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceSuggestions
  alias SocialScribe.Integrations.Suggestions

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  @full_contact %{
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

      result = SalesforceSuggestions.merge_with_contact(suggestions, @full_contact)

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
          new_value: "john@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      result = SalesforceSuggestions.merge_with_contact(suggestions, @full_contact)
      assert result == []
    end

    test "handles empty suggestions list" do
      result = SalesforceSuggestions.merge_with_contact([], @full_contact)
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

      result = SalesforceSuggestions.merge_with_contact(suggestions, @full_contact)
      assert length(result) == 1
      suggestion = hd(result)
      assert suggestion.apply == true
      assert suggestion.has_change == true
      assert suggestion.new_value == "CTO"
    end

    test "populates current_value from contact data" do
      contact = %{@full_contact | phone: "555-0000"}

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

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert length(result) == 1
      assert hd(result).current_value == "555-0000"
    end

    test "handles multiple changed fields" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Phone mentioned",
          apply: false,
          has_change: true
        },
        %{
          field: "Title",
          label: "Job Title",
          current_value: nil,
          new_value: "VP Engineering",
          context: "Promoted to VP",
          apply: false,
          has_change: true
        },
        %{
          field: "MailingCity",
          label: "Mailing City",
          current_value: nil,
          new_value: "San Francisco",
          context: "Moved to SF",
          apply: false,
          has_change: true
        }
      ]

      result = SalesforceSuggestions.merge_with_contact(suggestions, @full_contact)
      assert length(result) == 3
      assert Enum.all?(result, fn s -> s.apply == true end)
      assert Enum.all?(result, fn s -> s.has_change == true end)
    end

    test "filters nil new_value that matches nil current_value" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: nil,
          context: "No phone found",
          apply: false,
          has_change: true
        }
      ]

      result = SalesforceSuggestions.merge_with_contact(suggestions, @full_contact)
      assert result == []
    end

    test "preserves context and label from original suggestion" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone Number",
          current_value: nil,
          new_value: "555-1234",
          context: "Said during intro",
          apply: false,
          has_change: true
        }
      ]

      result = SalesforceSuggestions.merge_with_contact(suggestions, @full_contact)
      assert length(result) == 1
      assert hd(result).context == "Said during intro"
      assert hd(result).label == "Phone Number"
    end
  end

  describe "generate_suggestions_from_meeting/2" do
    test "returns suggestions from AI with proper formatting" do
      meeting = %{id: "meeting-1", transcript: "John's phone is 555-1234"}

      contact = %{
        id: "003XX0000012345",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil
      }

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting, _contact ->
        {:ok,
         [
           %{field: "Phone", value: "555-1234", context: "Mentioned phone number"},
           %{field: "Title", value: "CTO", context: "Introduced as CTO"}
         ]}
      end)

      {:ok, suggestions} =
        SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)

      assert length(suggestions) == 2

      phone_suggestion = Enum.find(suggestions, &(&1.field == "Phone"))
      assert phone_suggestion.new_value == "555-1234"
      assert phone_suggestion.label == "Phone"
      assert phone_suggestion.context == "Mentioned phone number"
      assert phone_suggestion.apply == true
      assert phone_suggestion.has_change == true
      assert phone_suggestion.current_value == nil

      title_suggestion = Enum.find(suggestions, &(&1.field == "Title"))
      assert title_suggestion.new_value == "CTO"
      assert title_suggestion.label == "Job Title"
    end

    test "returns error when AI generation fails" do
      meeting = %{id: "meeting-1"}
      contact = %{id: "003XX0000012345", firstname: "John"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting, _contact ->
        {:error, :ai_unavailable}
      end)

      assert {:error, :ai_unavailable} =
               SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)
    end

    test "returns empty suggestions when AI returns empty list" do
      meeting = %{id: "meeting-1"}
      contact = %{id: "003XX0000012345", firstname: "John"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting, _contact ->
        {:ok, []}
      end)

      {:ok, suggestions} =
        SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)

      assert suggestions == []
    end

    test "uses field_labels for label lookup" do
      meeting = %{id: "meeting-1"}
      contact = %{id: "003XX0000012345"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting, _contact ->
        {:ok,
         [
           %{field: "AssistantName", value: "Alice", context: "Assistant introduced"}
         ]}
      end)

      {:ok, suggestions} =
        SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)

      assert hd(suggestions).label == "Assistant Name"
    end

    test "falls back to field name when label not found" do
      meeting = %{id: "meeting-1"}
      contact = %{id: "003XX0000012345"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting, _contact ->
        {:ok,
         [
           %{field: "CustomField__c", value: "custom", context: "Custom field"}
         ]}
      end)

      {:ok, suggestions} =
        SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)

      assert hd(suggestions).label == "CustomField__c"
    end

    test "preserves timestamp from AI suggestions" do
      meeting = %{id: "meeting-1"}
      contact = %{id: "003XX0000012345"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting, _contact ->
        {:ok,
         [
           %{
             field: "Phone",
             value: "555-1234",
             context: "Phone mentioned",
             timestamp: "00:05:30"
           }
         ]}
      end)

      {:ok, suggestions} =
        SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)

      assert hd(suggestions).timestamp == "00:05:30"
    end
  end

  describe "generate_suggestions/3 (via Suggestions module)" do
    # SalesforceSuggestions.generate_suggestions/3 delegates to
    # Suggestions.generate_suggestions(SalesforceProvider, ...) which calls
    # SalesforceProvider.get_contact -> SalesforceApi.get_contact directly.
    # We test the orchestration logic through the Suggestions module with
    # the SalesforceProvider to verify the full pipeline.

    test "orchestration: fetches contact, generates AI suggestions, and filters unchanged" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = %{id: "meeting-1", transcript: "John's phone is 555-1234"}

      contact = %{
        id: "003XX0000012345",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
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
        display_name: "John Doe"
      }

      # Mock the behaviour-based API (used for search/apply in LiveView)
      # but for generate_suggestions the SalesforceProvider calls SalesforceApi directly.
      # So we test through the Suggestions module with a test provider.
      defmodule TestProvider do
        @behaviour SocialScribe.Integrations.Suggestions.Provider

        def field_labels,
          do: SocialScribe.Integrations.Suggestions.SalesforceProvider.field_labels()

        def get_contact(_credential, _contact_id) do
          {:ok,
           %{
             id: "003XX0000012345",
             firstname: "John",
             lastname: "Doe",
             email: "john@example.com",
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
             display_name: "John Doe"
           }}
        end

        def ai_suggestions(_meeting, _contact) do
          {:ok,
           [
             %{field: "Phone", value: "555-1234", context: "New phone number"},
             %{field: "Email", value: "john@example.com", context: "Same email"}
           ]}
        end

        def get_contact_field(contact, field) do
          SocialScribe.Integrations.Suggestions.SalesforceProvider.get_contact_field(
            contact,
            field
          )
        end
      end

      {:ok, %{contact: returned_contact, suggestions: suggestions}} =
        Suggestions.generate_suggestions(TestProvider, credential, "003XX0000012345", meeting)

      assert returned_contact.id == "003XX0000012345"

      # Phone changed (555-0000 -> 555-1234), should be included
      assert length(suggestions) == 1
      phone_suggestion = hd(suggestions)
      assert phone_suggestion.field == "Phone"
      assert phone_suggestion.new_value == "555-1234"
      assert phone_suggestion.current_value == "555-0000"
      assert phone_suggestion.has_change == true

      # Email unchanged, should be filtered
      refute Enum.any?(suggestions, &(&1.field == "Email"))
    end

    test "orchestration: returns error when get_contact fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = %{id: "meeting-1"}

      defmodule FailGetContactProvider do
        @behaviour SocialScribe.Integrations.Suggestions.Provider

        def field_labels,
          do: SocialScribe.Integrations.Suggestions.SalesforceProvider.field_labels()

        def get_contact(_credential, _contact_id), do: {:error, :not_found}
        def ai_suggestions(_meeting, _contact), do: {:ok, []}
        def get_contact_field(_contact, _field), do: nil
      end

      assert {:error, :not_found} =
               Suggestions.generate_suggestions(
                 FailGetContactProvider,
                 credential,
                 "003XX0000012345",
                 meeting
               )
    end

    test "orchestration: returns error when AI generation fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = %{id: "meeting-1"}

      defmodule FailAIProvider do
        @behaviour SocialScribe.Integrations.Suggestions.Provider

        def field_labels,
          do: SocialScribe.Integrations.Suggestions.SalesforceProvider.field_labels()

        def get_contact(_credential, _contact_id), do: {:ok, %{id: "003XX0000012345"}}
        def ai_suggestions(_meeting, _contact), do: {:error, :rate_limited}
        def get_contact_field(_contact, _field), do: nil
      end

      assert {:error, :rate_limited} =
               Suggestions.generate_suggestions(
                 FailAIProvider,
                 credential,
                 "003XX0000012345",
                 meeting
               )
    end

    test "orchestration: returns empty suggestions when all match current" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = %{id: "meeting-1"}

      defmodule AllMatchProvider do
        @behaviour SocialScribe.Integrations.Suggestions.Provider

        def field_labels,
          do: SocialScribe.Integrations.Suggestions.SalesforceProvider.field_labels()

        def get_contact(_credential, _contact_id) do
          {:ok,
           %{
             id: "003XX0000012345",
             phone: "555-1234",
             email: "john@example.com",
             firstname: nil,
             lastname: nil,
             mobilephone: nil,
             title: nil,
             department: nil,
             mailing_street: nil,
             mailing_city: nil,
             mailing_state: nil,
             mailing_postal_code: nil,
             mailing_country: nil,
             company: nil,
             display_name: "John"
           }}
        end

        def ai_suggestions(_meeting, _contact) do
          {:ok,
           [
             %{field: "Phone", value: "555-1234", context: "Unchanged"},
             %{field: "Email", value: "john@example.com", context: "Unchanged"}
           ]}
        end

        def get_contact_field(contact, field) do
          SocialScribe.Integrations.Suggestions.SalesforceProvider.get_contact_field(
            contact,
            field
          )
        end
      end

      {:ok, %{suggestions: suggestions}} =
        Suggestions.generate_suggestions(
          AllMatchProvider,
          credential,
          "003XX0000012345",
          meeting
        )

      assert suggestions == []
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
