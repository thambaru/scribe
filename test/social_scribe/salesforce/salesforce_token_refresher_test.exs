defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential as-is when expiry is far in the future" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 86400, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
      assert result.refresh_token == credential.refresh_token
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old_sf_token",
          refresh_token: "old_sf_refresh"
        })

      attrs = %{
        token: "new_sf_access_token",
        refresh_token: "new_sf_refresh_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)
      assert updated.token == "new_sf_access_token"
      assert updated.refresh_token == "new_sf_refresh_token"
      assert updated.id == credential.id
    end

    test "preserves metadata when updating credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{"instance_url" => "https://na1.salesforce.com"}
        })

      attrs = %{
        token: "refreshed_token",
        metadata: %{"instance_url" => "https://na2.salesforce.com"}
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)
      assert updated.token == "refreshed_token"
      assert updated.metadata["instance_url"] == "https://na2.salesforce.com"
    end
  end
end
