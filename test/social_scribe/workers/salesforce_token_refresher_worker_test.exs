defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.Workers.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "succeeds when no credentials are expiring" do
      # No Salesforce credentials exist, so worker should complete without errors
      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "succeeds when credentials have valid tokens (not expiring soon)" do
      user = user_fixture()

      _credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      # Token expires in 1 hour, well beyond the 10-minute threshold
      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end
  end

  describe "credential storage" do
    test "salesforce credential is stored with correct provider" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{"instance_url" => "https://na1.salesforce.com"}
        })

      assert credential.provider == "salesforce"
      assert credential.metadata["instance_url"] == "https://na1.salesforce.com"
    end

    test "salesforce credential can be updated with new token" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      new_expires = DateTime.add(DateTime.utc_now(), 7200, :second)

      {:ok, updated} =
        Accounts.update_user_credential(credential, %{
          token: "new_salesforce_token",
          expires_at: new_expires
        })

      assert updated.token == "new_salesforce_token"
      assert updated.id == credential.id
    end

    test "salesforce credential can update metadata with new instance_url" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{"instance_url" => "https://na1.salesforce.com"}
        })

      {:ok, updated} =
        Accounts.update_user_credential(credential, %{
          metadata: %{"instance_url" => "https://cs42.salesforce.com"}
        })

      assert updated.metadata["instance_url"] == "https://cs42.salesforce.com"
    end
  end
end
