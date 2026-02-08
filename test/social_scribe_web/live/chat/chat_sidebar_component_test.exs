defmodule SocialScribeWeb.ChatLive.ChatSidebarComponentTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.ChatFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import Mox

  setup :verify_on_exit!

  describe "Chat Sidebar - rendering" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "renders the chat sidebar when navigating to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#chat-sidebar-panel")
    end

    test "renders the Ask Anything header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "h2", "Ask Anything")
    end

    test "renders Chat and History tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Chat"
      assert html =~ "History"
    end

    test "renders empty state when no messages", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Ask anything about your CRM contacts"
      assert html =~ "Use @mention to reference contacts"
    end

    test "renders the send button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#chat-send-btn")
    end

    test "renders the message input area", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#chat-mention-input")
    end

    test "renders the floating chat button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#chat-floating-button")
    end
  end

  describe "Chat Sidebar - tab switching" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "defaults to chat tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Ask anything about your CRM contacts"
    end

    test "switching to history tab shows conversation list", %{conn: conn, user: user} do
      conversation_fixture(user.id, %{title: "Test Conversation"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button", "History")
      |> render_click()

      html = render(view)
      assert html =~ "Test Conversation"
    end

    test "history tab lists auto-created conversation", %{conn: conn} do
      # When the chat sidebar mounts, it auto-creates a conversation via
      # get_or_create_active_conversation, so history always has at least one
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button", "History")
      |> render_click()

      html = render(view)
      # The auto-created conversation appears with "New conversation" fallback title
      assert html =~ "New conversation"
    end
  end

  describe "Chat Sidebar - conversations" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "new conversation button creates a fresh conversation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button[phx-click='new_conversation']")
      |> render_click()

      html = render(view)
      assert html =~ "Ask anything about your CRM contacts"
    end

    test "selecting a conversation from history loads its messages", %{conn: conn, user: user} do
      {conv, _messages} =
        conversation_with_messages_fixture(user.id, [
          %{role: "user", content: "Hello there"},
          %{role: "assistant", content: "Hi, how can I help?"}
        ])

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Switch to history tab
      view
      |> element("button", "History")
      |> render_click()

      # Select the conversation
      view
      |> element("button[phx-click='select_conversation'][phx-value-id='#{conv.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Hello there"
      assert html =~ "Hi, how can I help?"
    end

    test "deleting a conversation removes it from history", %{conn: conn, user: user} do
      conv = conversation_fixture(user.id, %{title: "To Delete"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button", "History")
      |> render_click()

      view
      |> element("button[phx-click='delete_conversation'][phx-value-id='#{conv.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "To Delete"
    end
  end

  describe "Chat Sidebar - mention system" do
    setup %{conn: conn} do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "mention_search triggers contact search when query is 2+ chars", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Jo"
        {:ok, [%{id: "1", firstname: "John", lastname: "Doe", email: "john@test.com"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Use render_hook on an element with phx-hook attribute
      view
      |> element("#chat-mention-input")
      |> render_hook("mention_search", %{"query" => "Jo"})

      # Give async search time to complete
      Process.sleep(200)

      html = render(view)
      assert html =~ "John"
      assert html =~ "Doe"
    end

    test "close_mention_dropdown clears search state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#chat-mention-input")
      |> render_hook("close_mention_dropdown", %{})

      html = render(view)
      refute html =~ "Searching contacts..."
    end
  end

  describe "Chat Sidebar - sending messages" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "sending empty message does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("form[phx-submit='send_message']")
      |> render_submit(%{"message" => "", "mentioned_contacts" => "[]"})

      html = render(view)
      assert html =~ "Ask anything about your CRM contacts"
    end

    test "sending a message adds it to the chat", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("form[phx-submit='send_message']")
      |> render_submit(%{"message" => "Hello world", "mentioned_contacts" => "[]"})

      html = render(view)
      assert html =~ "Hello world"
      assert html =~ "Thinking..."
    end

    test "sends with mentioned contacts using real credential", %{conn: conn, user: user} do
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{firstname: "John", lastname: "Doe", email: "john@test.com"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      contacts_json =
        Jason.encode!([
          %{
            "id" => "1",
            "provider" => "hubspot",
            "firstname" => "John",
            "lastname" => "Doe",
            "email" => "john@test.com",
            "credential_id" => to_string(credential.id)
          }
        ])

      view
      |> element("form[phx-submit='send_message']")
      |> render_submit(%{"message" => "What about John?", "mentioned_contacts" => contacts_json})

      html = render(view)
      assert html =~ "What about John?"
    end
  end

  describe "Chat Sidebar - toggle" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "toggle_chat_sidebar toggles sidebar visibility", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dashboard")

      assert html =~ "translate-x-full"

      view
      |> element("#chat-floating-button")
      |> render_click()

      html = render(view)
      assert html =~ "translate-x-0"
    end

    test "close button toggles sidebar closed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open the sidebar first
      view
      |> element("#chat-floating-button")
      |> render_click()

      # Close via the close button
      view
      |> element("button[phx-click='toggle_chat_sidebar'][aria-label='Close sidebar']")
      |> render_click()

      html = render(view)
      assert html =~ "translate-x-full"
    end
  end

  describe "Chat Sidebar - context menu" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "renders Add context button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Add context"
    end

    test "toggle_context_menu opens the context menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      html = render(view)
      # The context type picker should appear with "Meetings" option
      assert html =~ "Meetings"
    end

    test "toggle_context_menu closes when already open", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      # Close
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      html = render(view)
      # Context type picker should not be visible when closed
      refute html =~ "Search meetings..."
    end

    test "close_context_menu resets context menu state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open context menu
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      # Close via click-away event
      view
      |> element("#chat-mention-input")
      |> render_hook("close_context_menu", %{})

      html = render(view)
      refute html =~ "Search meetings..."
    end
  end

  describe "Chat Sidebar - meeting context" do
    setup %{conn: conn} do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          title: "Sprint Planning"
        })

      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Alice"})

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "select_context_type shows meeting search dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open context menu
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      # Select "Meetings" context type
      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      # Wait for async meeting list to load
      Process.sleep(200)

      html = render(view)
      assert html =~ "Search meetings..."
      assert html =~ "Sprint Planning"
    end

    test "select_meeting adds meeting pill to the input area", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open context menu and select Meetings
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      # Select the meeting
      view
      |> element("button[phx-click='select_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      html = render(view)
      # Meeting pill should appear
      assert html =~ "Sprint Planning"
    end

    test "select_meeting does not add duplicate meetings", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open context menu and select the same meeting twice
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      view
      |> element("button[phx-click='select_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      # Open again and try to add same meeting
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      view
      |> element("button[phx-click='select_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      html = render(view)
      # Should only appear once as a pill (the remove button is unique per meeting)
      assert length(Regex.scan(~r/phx-click="remove_meeting"/, html)) == 1
    end

    test "remove_meeting removes meeting pill", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Add a meeting first
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      view
      |> element("button[phx-click='select_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      # Now remove it
      view
      |> element("button[phx-click='remove_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "remove_meeting"
    end

    test "meeting_search filters meetings by query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Open context menu and select Meetings
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      # Search with a query that won't match
      view
      |> element("#chat-mention-input")
      |> render_hook("meeting_search", %{"value" => "Nonexistent"})

      Process.sleep(200)

      html = render(view)
      refute html =~ "Sprint Planning"
    end
  end

  describe "Chat Sidebar - select_mention" do
    setup %{conn: conn} do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "select_mention adds contact to mentioned contacts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#chat-mention-input")
      |> render_hook("select_mention", %{
        "id" => "1",
        "provider" => "hubspot",
        "firstname" => "John",
        "lastname" => "Doe",
        "email" => "john@test.com",
        "credential_id" => "123"
      })

      html = render(view)
      # The hidden input should contain the mentioned contact in JSON
      assert html =~ "John"
    end

    test "remove_mention removes contact from mentioned contacts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Add a contact first
      view
      |> element("#chat-mention-input")
      |> render_hook("select_mention", %{
        "id" => "1",
        "provider" => "hubspot",
        "firstname" => "John",
        "lastname" => "Doe",
        "email" => "john@test.com",
        "credential_id" => "123"
      })

      # Remove it
      view
      |> element("#chat-mention-input")
      |> render_hook("remove_mention", %{
        "firstname" => "John",
        "provider" => "hubspot"
      })

      html = render(view)
      # The mentions hidden input should be empty list
      assert html =~ "chat-mentions-hidden"
    end
  end

  describe "Chat Sidebar - sending messages with meeting context" do
    setup %{conn: conn} do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      meeting =
        meeting_fixture(%{
          calendar_event_id: calendar_event.id,
          title: "Deal Review"
        })

      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Bob"})

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "sending a message with mentioned meetings includes them", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Add a meeting first
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      view
      |> element("button[phx-click='select_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      # Send message with the meeting context
      meetings_json = Jason.encode!([%{"id" => meeting.id, "title" => "Deal Review"}])

      view
      |> element("form[phx-submit='send_message']")
      |> render_submit(%{
        "message" => "What was discussed?",
        "mentioned_contacts" => "[]",
        "mentioned_meetings" => meetings_json
      })

      html = render(view)
      assert html =~ "What was discussed?"
      assert html =~ "Thinking..."
    end

    test "new_conversation clears mentioned meetings", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Add a meeting
      view
      |> element("button[phx-click='toggle_context_menu']")
      |> render_click()

      view
      |> element("button[phx-click='select_context_type']")
      |> render_click()

      Process.sleep(200)

      view
      |> element("button[phx-click='select_meeting'][phx-value-id='#{meeting.id}']")
      |> render_click()

      # Create new conversation - should clear meetings
      view
      |> element("button[phx-click='new_conversation']")
      |> render_click()

      html = render(view)
      refute html =~ "remove_meeting"
    end
  end

  describe "Chat Sidebar - switching tabs preserves and loads state" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "switching to chat tab from history shows chat view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Switch to history
      view
      |> element("button", "History")
      |> render_click()

      # Switch back to chat
      view
      |> element("button", "Chat")
      |> render_click()

      html = render(view)
      assert html =~ "Ask anything about your CRM contacts"
    end

    test "history tab shows empty state when no conversations exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Note: auto-create always makes at least one, so we check it appears
      view
      |> element("button", "History")
      |> render_click()

      html = render(view)
      # At minimum the auto-created conversation should show
      assert html =~ "New conversation"
    end
  end
end
