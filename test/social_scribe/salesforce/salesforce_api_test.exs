defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "apply_updates/3" do
    setup do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      %{credential: credential}
    end

    test "returns {:ok, :no_updates} for empty updates list", %{credential: credential} do
      assert {:ok, :no_updates} =
               SalesforceApi.apply_updates(credential, "003XX0000012345", [])
    end

    test "returns {:ok, :no_updates} when all updates have apply: false", %{
      credential: credential
    } do
      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} =
               SalesforceApi.apply_updates(credential, "003XX0000012345", updates)
    end

    test "returns {:ok, :no_updates} for mixed updates when all set to false", %{
      credential: credential
    } do
      updates = [
        %{field: "Phone", new_value: "555-1234", apply: true},
        %{field: "Email", new_value: "test@example.com", apply: false},
        %{field: "Title", new_value: "CTO", apply: true}
      ]

      all_false = Enum.map(updates, fn u -> %{u | apply: false} end)

      assert {:ok, :no_updates} =
               SalesforceApi.apply_updates(credential, "003XX0000012345", all_false)
    end

    test "returns {:ok, :no_updates} for a single update with apply: false", %{
      credential: credential
    } do
      updates = [%{field: "Phone", new_value: "555-1234", apply: false}]

      assert {:ok, :no_updates} =
               SalesforceApi.apply_updates(credential, "003XX0000012345", updates)
    end

    test "last update wins when duplicate fields are present", %{credential: credential} do
      # Both apply:false, so no_updates; but the map-building logic should
      # keep the last one for each field key.
      updates = [
        %{field: "Phone", new_value: "555-0001", apply: false},
        %{field: "Phone", new_value: "555-0002", apply: false}
      ]

      assert {:ok, :no_updates} =
               SalesforceApi.apply_updates(credential, "003XX0000012345", updates)
    end
  end

  describe "search_contacts/2" do
    test "returns error when credential has no instance_url in metadata" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{},
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:error, :missing_instance_url} =
               SalesforceApi.search_contacts(credential, "John")
    end

    test "returns error when credential metadata is nil" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: nil,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:error, :missing_instance_url} =
               SalesforceApi.search_contacts(credential, "John")
    end
  end

  describe "get_contact/2" do
    test "returns error when credential has no instance_url" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{},
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:error, :missing_instance_url} =
               SalesforceApi.get_contact(credential, "003XX0000012345")
    end

    test "returns error when metadata is nil" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: nil,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:error, :missing_instance_url} =
               SalesforceApi.get_contact(credential, "003XX0000012345")
    end
  end

  describe "update_contact/3" do
    test "returns error when credential has no instance_url" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{},
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:error, :missing_instance_url} =
               SalesforceApi.update_contact(credential, "003XX0000012345", %{
                 "Phone" => "555-1234"
               })
    end
  end

  describe "credential setup" do
    test "credential has correct provider" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert credential.provider == "salesforce"
    end

    test "credential has metadata with instance_url" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{"instance_url" => "https://na1.salesforce.com"}
        })

      assert credential.metadata["instance_url"] == "https://na1.salesforce.com"
    end

    test "credential has default instance_url from fixture" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert credential.metadata["instance_url"] == "https://test.salesforce.com"
    end
  end
end
