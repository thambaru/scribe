defmodule SocialScribe.Chat.ContactSearch do
  @moduledoc """
  Searches both HubSpot and Salesforce CRMs in parallel for contacts.
  Results are tagged with their provider for display in the chat sidebar.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  @max_results 10

  @doc """
  Searches connected CRMs for contacts matching the query.
  Returns a combined, deduplicated list tagged with provider info.

  Each result has the shape:
    %{id: string, firstname: string, lastname: string, email: string,
      provider: :hubspot | :salesforce, credential_id: integer}
  """
  def search(user_id, query) when is_binary(query) and byte_size(query) > 0 do
    hubspot_credential = Accounts.get_user_hubspot_credential(user_id)
    salesforce_credential = Accounts.get_user_salesforce_credential(user_id)

    tasks =
      []
      |> maybe_add_task(:hubspot, hubspot_credential, query)
      |> maybe_add_task(:salesforce, salesforce_credential, query)

    results =
      tasks
      |> Task.await_many(10_000)
      |> List.flatten()
      |> Enum.take(@max_results)

    {:ok, results}
  end

  def search(_user_id, _query), do: {:ok, []}

  defp maybe_add_task(tasks, :hubspot, nil, _query), do: tasks

  defp maybe_add_task(tasks, :hubspot, credential, query) do
    task =
      Task.async(fn ->
        case HubspotApi.search_contacts(credential, query) do
          {:ok, contacts} ->
            Enum.map(contacts, fn c ->
              %{
                id: c.id || c[:id],
                firstname: c.firstname || c[:firstname] || "",
                lastname: c.lastname || c[:lastname] || "",
                email: c.email || c[:email] || "",
                provider: :hubspot,
                credential_id: credential.id
              }
            end)

          {:error, _} ->
            []
        end
      end)

    tasks ++ [task]
  end

  defp maybe_add_task(tasks, :salesforce, nil, _query), do: tasks

  defp maybe_add_task(tasks, :salesforce, credential, query) do
    task =
      Task.async(fn ->
        case SalesforceApi.search_contacts(credential, query) do
          {:ok, contacts} ->
            Enum.map(contacts, fn c ->
              %{
                id: c.id || c[:id],
                firstname: c.firstname || c[:firstname] || "",
                lastname: c.lastname || c[:lastname] || "",
                email: c.email || c[:email] || "",
                provider: :salesforce,
                credential_id: credential.id
              }
            end)

          {:error, _} ->
            []
        end
      end)

    tasks ++ [task]
  end
end
