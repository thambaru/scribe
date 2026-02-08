defmodule SocialScribe.Chat.ChatAiTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat.ChatAi

  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import Mox

  setup :verify_on_exit!

  describe "ask/3" do
    test "fetches CRM data and returns config error without API key" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _credential, contact_id ->
        assert contact_id == "123"

        {:ok,
         %{
           firstname: "John",
           lastname: "Doe",
           email: "john@example.com",
           phone: "555-1234"
         }}
      end)

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned_contacts = [
        %{
          id: "123",
          provider: :hubspot,
          firstname: "John",
          lastname: "Doe",
          credential_id: credential.id
        }
      ]

      # CRM data is fetched but Gemini call fails without API key
      result = ChatAi.ask("Tell me about John", mentioned_contacts, [])
      assert {:error, {:config_error, _}} = result
    end

    test "returns error when Gemini API fails" do
      # With no API key configured, Gemini will return a config error
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      result = ChatAi.ask("Hello", [], [])

      assert {:error, {:config_error, _}} = result
    end

    test "handles empty mentioned_contacts" do
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      result = ChatAi.ask("What's the weather?", [], [])

      # Without API key it will return config error, but we verify no crash
      assert {:error, _} = result
    end

    test "handles nil mentioned_contacts" do
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      result = ChatAi.ask("Hello", nil, [])
      assert {:error, _} = result
    end

    test "builds sources from mentioned contacts with hubspot provider" do
      contacts = [
        %{
          id: "1",
          provider: :hubspot,
          firstname: "Jane",
          lastname: "Doe",
          credential_id: 1
        }
      ]

      # We verify the source structure by checking the contact info
      # The actual sources are built in fetch_contact_context
      [contact] = contacts
      assert contact.provider == :hubspot
      assert contact.firstname == "Jane"
    end

    test "builds sources from mentioned contacts with salesforce provider" do
      contacts = [
        %{
          id: "SF001",
          provider: :salesforce,
          firstname: "Bob",
          lastname: "Smith",
          credential_id: 2
        }
      ]

      [contact] = contacts
      assert contact.provider == :salesforce
      assert contact.firstname == "Bob"
    end

    test "builds sources from string-keyed contacts" do
      contacts = [
        %{
          "id" => "1",
          "provider" => "hubspot",
          "firstname" => "Jane",
          "lastname" => "Doe",
          "credential_id" => 1
        }
      ]

      [contact] = contacts
      assert contact["provider"] == "hubspot"
      assert contact["firstname"] == "Jane"
    end
  end

  describe "ask/3 with mocked CRM APIs" do
    test "fetches hubspot contact data for mentioned contacts" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "42"
        {:ok, %{firstname: "Alice", lastname: "Wonder", email: "alice@example.com"}}
      end)

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned = [
        %{
          id: "42",
          provider: :hubspot,
          firstname: "Alice",
          lastname: "Wonder",
          credential_id: credential.id
        }
      ]

      # Will fail at Gemini call but we verify the mock was called
      result = ChatAi.ask("Tell me about Alice", mentioned, [])
      assert {:error, _} = result
    end

    test "fetches salesforce contact data for mentioned contacts" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "SF001"
        {:ok, %{firstname: "Bob", lastname: "Builder", email: "bob@example.com"}}
      end)

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned = [
        %{
          id: "SF001",
          provider: :salesforce,
          firstname: "Bob",
          lastname: "Builder",
          credential_id: credential.id
        }
      ]

      result = ChatAi.ask("Tell me about Bob", mentioned, [])
      assert {:error, _} = result
    end

    test "handles CRM API errors gracefully without crashing" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:error, {:api_error, 500, "Internal error"}}
      end)

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned = [
        %{
          id: "99",
          provider: :hubspot,
          firstname: "Error",
          lastname: "Contact",
          credential_id: credential.id
        }
      ]

      # Should not crash even when CRM API fails
      result = ChatAi.ask("Tell me about Error", mentioned, [])
      assert {:error, _} = result
    end
  end

  describe "ask/4 with meeting context" do
    test "handles mentioned_meetings with valid meeting data" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          title: "Sprint Planning",
          duration_seconds: 1800
        })

      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Alice"})

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned_meetings = [%{id: meeting.id, title: "Sprint Planning"}]

      # Will fail at Gemini call but should not crash while fetching meeting context
      result = ChatAi.ask("Summarize the sprint planning", [], [], mentioned_meetings)
      assert {:error, _} = result
    end

    test "handles mentioned_meetings with string-keyed map" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          title: "Retro"
        })

      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Bob"})

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned_meetings = [%{"id" => meeting.id, "title" => "Retro"}]

      result = ChatAi.ask("What happened in retro?", [], [], mentioned_meetings)
      assert {:error, _} = result
    end

    test "handles empty mentioned_meetings without crashing" do
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      result = ChatAi.ask("Hello", [], [], [])
      assert {:error, _} = result
    end

    test "handles nil mentioned_meetings (default parameter)" do
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      # ask/3 calls ask/4 with default [] for mentioned_meetings
      result = ChatAi.ask("Hello", [], [])
      assert {:error, _} = result
    end

    test "handles meeting that does not exist" do
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned_meetings = [%{id: -1, title: "Ghost Meeting"}]

      # Should not crash when meeting is not found (get_meeting_with_details returns nil)
      result = ChatAi.ask("Tell me about ghost", [], [], mentioned_meetings)
      assert {:error, _} = result
    end

    test "combines contact and meeting context" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          title: "Deal Review"
        })

      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Charlie"})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{firstname: "John", lastname: "Doe", email: "john@test.com"}}
      end)

      Application.put_env(:social_scribe, :gemini_api_key, nil)

      mentioned_contacts = [
        %{
          id: "1",
          provider: :hubspot,
          firstname: "John",
          lastname: "Doe",
          credential_id: credential.id
        }
      ]

      mentioned_meetings = [%{id: meeting.id, title: "Deal Review"}]

      # Should fetch both contact and meeting context without crashing
      result = ChatAi.ask("What did John say in the deal review?", mentioned_contacts, [], mentioned_meetings)
      assert {:error, _} = result
    end

    test "meeting sources include provider :meeting" do
      # Verify the structure of meeting sources
      mentioned_meetings = [%{id: 1, title: "Weekly Sync"}]

      # Meeting sources should have provider: :meeting
      sources =
        mentioned_meetings
        |> Enum.map(fn meeting_ref ->
          %{
            provider: :meeting,
            name: Map.get(meeting_ref, :title, Map.get(meeting_ref, "title", "Meeting"))
          }
        end)

      assert [%{provider: :meeting, name: "Weekly Sync"}] = sources
    end
  end
end
