defmodule SocialScribeWeb.ChatLive.ChatSidebarComponentTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.ChatFixtures
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
end
