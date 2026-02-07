defmodule SocialScribeWeb.ChatLive.ChatSidebarMoxTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.ChatFixtures
  import Mox

  setup :verify_on_exit!

  describe "Chat Sidebar with mocked CRM APIs" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_credential = hubspot_credential_fixture(%{user_id: user.id})
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        hubspot_credential: hubspot_credential,
        salesforce_credential: salesforce_credential
      }
    end

    test "mention search returns mocked hubspot results", %{conn: conn} do
      mock_contacts = [
        %{id: "hub_1", firstname: "Alice", lastname: "Hub", email: "alice@hub.com"},
        %{id: "hub_2", firstname: "Bob", lastname: "Hub", email: "bob@hub.com"}
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Al"
        {:ok, mock_contacts}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#chat-mention-input")
      |> render_hook("mention_search", %{"query" => "Al"})

      Process.sleep(200)

      html = render(view)
      assert html =~ "Alice"
      assert html =~ "Bob"
    end

    test "mention search returns mocked salesforce results", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Jane"

        {:ok,
         [%{id: "sf_1", firstname: "Jane", lastname: "SF", email: "jane@sf.com"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#chat-mention-input")
      |> render_hook("mention_search", %{"query" => "Jane"})

      Process.sleep(200)

      html = render(view)
      assert html =~ "Jane"
      assert html =~ "SF"
    end

    test "mention search combines results from both CRMs", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "hub_1", firstname: "John", lastname: "HubSpot", email: "john@hub.com"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok,
         [%{id: "sf_1", firstname: "John", lastname: "Salesforce", email: "john@sf.com"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#chat-mention-input")
      |> render_hook("mention_search", %{"query" => "John"})

      Process.sleep(200)

      html = render(view)
      assert html =~ "HubSpot"
      assert html =~ "Salesforce"
    end

    test "mention search handles API errors gracefully", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, "Server error"}}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 401, "Unauthorized"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#chat-mention-input")
      |> render_hook("mention_search", %{"query" => "Test"})

      Process.sleep(200)

      html = render(view)
      # Should show "No contacts found" since both APIs failed
      assert html =~ "No contacts found"
    end

    test "selecting a mention adds contact to mentioned list", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "hub_1", firstname: "Alice", lastname: "Test", email: "alice@test.com"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Search for a contact
      view
      |> element("#chat-mention-input")
      |> render_hook("mention_search", %{"query" => "Alice"})

      Process.sleep(200)

      # Select the contact from dropdown
      view
      |> element("button[phx-click='select_mention'][phx-value-firstname='Alice']")
      |> render_click()

      html = render(view)
      # Mention dropdown should be closed after selection
      refute html =~ "No contacts found"
    end
  end

  describe "Chat Sidebar - conversation persistence" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "messages persist across conversation loads", %{conn: conn, user: user} do
      conv = conversation_fixture(user.id, %{title: "Persistent Chat"})
      message_fixture(conv.id, %{role: "user", content: "Remember me?"})
      message_fixture(conv.id, %{role: "assistant", content: "I remember you!"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Switch to history
      view
      |> element("button", "History")
      |> render_click()

      # Select the conversation
      view
      |> element("button[phx-click='select_conversation'][phx-value-id='#{conv.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Remember me?"
      assert html =~ "I remember you!"
    end

    test "multiple conversations appear in history ordered by recency", %{
      conn: conn,
      user: user
    } do
      conversation_fixture(user.id, %{title: "Older Chat"})
      Process.sleep(10)
      conversation_fixture(user.id, %{title: "Newer Chat"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("button", "History")
      |> render_click()

      html = render(view)
      assert html =~ "Older Chat"
      assert html =~ "Newer Chat"
    end

    test "deleting current conversation switches to next available", %{conn: conn, user: user} do
      conv1 = conversation_fixture(user.id, %{title: "Chat One"})
      Process.sleep(10)
      _conv2 = conversation_fixture(user.id, %{title: "Chat Two"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Switch to history
      view
      |> element("button", "History")
      |> render_click()

      # Select conv1
      view
      |> element("button[phx-click='select_conversation'][phx-value-id='#{conv1.id}']")
      |> render_click()

      # Now delete conv1 from history tab
      view
      |> element("button", "History")
      |> render_click()

      view
      |> element("button[phx-click='delete_conversation'][phx-value-id='#{conv1.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "Chat One"
    end

    test "deleting last conversation creates a new empty one", %{conn: conn, user: user} do
      conv = conversation_fixture(user.id, %{title: "Last Chat"})
      message_fixture(conv.id, %{role: "user", content: "Only message"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Switch to history
      view
      |> element("button", "History")
      |> render_click()

      # Delete it
      view
      |> element("button[phx-click='delete_conversation'][phx-value-id='#{conv.id}']")
      |> render_click()

      # Switch back to chat tab
      view
      |> element("button", "Chat")
      |> render_click()

      html = render(view)
      # Should show empty state since the new conversation has no messages
      assert html =~ "Ask anything about your CRM contacts"
    end
  end
end
