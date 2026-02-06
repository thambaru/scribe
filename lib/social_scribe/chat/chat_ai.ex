defmodule SocialScribe.Chat.ChatAi do
  @moduledoc """
  Handles AI-powered chat responses using Google Gemini.
  Fetches full contact data from CRMs, builds prompts with context,
  and generates conversational responses.
  """

  alias SocialScribe.GeminiClient
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  @doc """
  Processes a user question with optional CRM contact context.

  Returns `{:ok, response_text, sources}` where sources is a list
  of `%{provider: atom, name: string}` maps indicating which CRMs were queried.
  """
  def ask(user_message, mentioned_contacts, conversation_history) do
    # Fetch full contact data from CRMs for mentioned contacts
    {contact_context, sources} = fetch_contact_context(mentioned_contacts)

    prompt = build_prompt(user_message, contact_context, conversation_history)

    case GeminiClient.generate(prompt) do
      {:ok, response_text} ->
        {:ok, response_text, sources}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_contact_context(mentioned_contacts) when is_list(mentioned_contacts) do
    results =
      mentioned_contacts
      |> Enum.map(fn contact ->
        Task.async(fn -> fetch_single_contact(contact) end)
      end)
      |> Task.await_many(15_000)

    contact_texts =
      results
      |> Enum.filter(fn {status, _} -> status == :ok end)
      |> Enum.map(fn {:ok, text} -> text end)

    sources =
      mentioned_contacts
      |> Enum.map(fn contact ->
        name =
          "#{Map.get(contact, :firstname, Map.get(contact, "firstname", ""))} #{Map.get(contact, :lastname, Map.get(contact, "lastname", ""))}"
          |> String.trim()

        provider =
          case Map.get(contact, :provider, Map.get(contact, "provider")) do
            p when is_atom(p) -> p
            p when is_binary(p) -> String.to_existing_atom(p)
            _ -> :unknown
          end

        %{provider: provider, name: name}
      end)

    context = Enum.join(contact_texts, "\n\n")
    {context, sources}
  end

  defp fetch_contact_context(_), do: {"", []}

  defp fetch_single_contact(contact) do
    provider = Map.get(contact, :provider, Map.get(contact, "provider"))
    contact_id = Map.get(contact, :id, Map.get(contact, "id"))
    credential_id = Map.get(contact, :credential_id, Map.get(contact, "credential_id"))

    credential = Accounts.get_user_credential!(credential_id)

    case normalize_provider(provider) do
      :hubspot ->
        case HubspotApi.get_contact(credential, to_string(contact_id)) do
          {:ok, data} -> {:ok, format_contact_data(:hubspot, data)}
          {:error, reason} -> {:error, reason}
        end

      :salesforce ->
        case SalesforceApi.get_contact(credential, to_string(contact_id)) do
          {:ok, data} -> {:ok, format_contact_data(:salesforce, data)}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :unknown_provider}
    end
  end

  defp normalize_provider(p) when is_atom(p), do: p
  defp normalize_provider("hubspot"), do: :hubspot
  defp normalize_provider("salesforce"), do: :salesforce
  defp normalize_provider(_), do: :unknown

  defp format_contact_data(provider, data) when is_map(data) do
    provider_label = provider |> to_string() |> String.capitalize()

    fields =
      data
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> "  - #{k}: #{v}" end)
      |> Enum.join("\n")

    """
    [#{provider_label} Contact]
    #{fields}
    """
  end

  defp build_prompt(user_message, contact_context, conversation_history) do
    history_text =
      conversation_history
      |> Enum.map(fn msg ->
        role = Map.get(msg, :role, Map.get(msg, "role", "user"))
        content = Map.get(msg, :content, Map.get(msg, "content", ""))
        "#{String.capitalize(role)}: #{content}"
      end)
      |> Enum.join("\n")

    """
    You are a helpful CRM assistant for a business professional. You help answer questions about their contacts and CRM data.

    Be concise, professional, and helpful. If you have contact data available, reference it specifically. If you don't have enough information to answer a question, say so clearly.

    #{if contact_context != "" do
      """
      CONTACT DATA:
      #{contact_context}
      """
    else
      ""
    end}

    #{if history_text != "" do
      """
      CONVERSATION HISTORY:
      #{history_text}
      """
    else
      ""
    end}

    User: #{user_message}

    Assistant:
    """
  end
end
