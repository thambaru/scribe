defmodule SocialScribe.Chat.ContactSearchTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat.ContactSearch

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "search/2" do
    test "returns empty list for empty query" do
      user = user_fixture()
      assert {:ok, []} = ContactSearch.search(user.id, "")
    end

    test "returns empty list for nil query" do
      user = user_fixture()
      assert {:ok, []} = ContactSearch.search(user.id, nil)
    end

    test "searches hubspot when user has hubspot credential" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      mock_contacts = [
        %{id: "hub_1", firstname: "John", lastname: "Doe", email: "john@example.com"}
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "John"
        {:ok, mock_contacts}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "John")
      assert length(results) == 1

      [contact] = results
      assert contact.provider == :hubspot
      assert contact.firstname == "John"
      assert contact.lastname == "Doe"
    end

    test "searches salesforce when user has salesforce credential" do
      user = user_fixture()
      _credential = salesforce_credential_fixture(%{user_id: user.id})

      mock_contacts = [
        %{id: "sf_1", firstname: "Jane", lastname: "Smith", email: "jane@example.com"}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Jane"
        {:ok, mock_contacts}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "Jane")
      assert length(results) == 1

      [contact] = results
      assert contact.provider == :salesforce
      assert contact.firstname == "Jane"
      assert contact.lastname == "Smith"
    end

    test "searches both CRMs when user has both credentials" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "hub_1", firstname: "John", lastname: "Doe", email: "john@hub.com"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "sf_1", firstname: "John", lastname: "Doe", email: "john@sf.com"}]}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "John")
      assert length(results) == 2

      providers = Enum.map(results, & &1.provider)
      assert :hubspot in providers
      assert :salesforce in providers
    end

    test "returns empty list when user has no CRM credentials" do
      user = user_fixture()
      assert {:ok, []} = ContactSearch.search(user.id, "John")
    end

    test "handles hubspot API error gracefully" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, "Server error"}}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "John")
      assert results == []
    end

    test "handles salesforce API error gracefully" do
      user = user_fixture()
      _credential = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 401, "Unauthorized"}}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "Jane")
      assert results == []
    end

    test "limits combined results to 10" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      hubspot_contacts =
        for i <- 1..8 do
          %{id: "hub_#{i}", firstname: "Hub#{i}", lastname: "Contact", email: "hub#{i}@test.com"}
        end

      salesforce_contacts =
        for i <- 1..8 do
          %{id: "sf_#{i}", firstname: "SF#{i}", lastname: "Contact", email: "sf#{i}@test.com"}
        end

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, hubspot_contacts}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, salesforce_contacts}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "Contact")
      assert length(results) == 10
    end

    test "tags each result with credential_id" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "hub_1", firstname: "Test", lastname: "User", email: "test@test.com"}]}
      end)

      assert {:ok, [contact]} = ContactSearch.search(user.id, "Test")
      assert contact.credential_id == credential.id
    end

    test "returns contacts with correct shape" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok,
         [
           %{
             id: "hub_1",
             firstname: "Alice",
             lastname: "Wonder",
             email: "alice@example.com"
           }
         ]}
      end)

      assert {:ok, [contact]} = ContactSearch.search(user.id, "Alice")

      assert Map.has_key?(contact, :id)
      assert Map.has_key?(contact, :firstname)
      assert Map.has_key?(contact, :lastname)
      assert Map.has_key?(contact, :email)
      assert Map.has_key?(contact, :provider)
      assert Map.has_key?(contact, :credential_id)
    end

    test "one CRM failing does not prevent results from the other" do
      user = user_fixture()
      _hubspot_cred = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce_cred = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, "HubSpot down"}}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "sf_1", firstname: "Jane", lastname: "Doe", email: "jane@test.com"}]}
      end)

      assert {:ok, results} = ContactSearch.search(user.id, "Jane")
      assert length(results) == 1
      assert hd(results).provider == :salesforce
    end
  end
end
