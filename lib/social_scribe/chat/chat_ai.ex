defmodule SocialScribe.Chat.ChatAi do
  @moduledoc """
  Handles AI-powered chat responses using Google Gemini.
  Fetches full contact data from CRMs, builds prompts with context,
  and generates conversational responses.
  """

  alias SocialScribe.GeminiClient
  alias SocialScribe.Accounts
  alias SocialScribe.Meetings
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  @doc """
  Processes a user question with optional CRM contact and meeting context.

  Returns `{:ok, response_text, sources}` where sources is a list
  of `%{provider: atom, name: string}` maps indicating which CRMs/meetings were queried.

  Accepts optional keyword opts:
    - `pronoun_contacts` — contacts carried over from previous messages purely
      for pronoun resolution. These provide AI context but do NOT appear in sources.
    - `context_meetings` — meetings carried over from previous messages for
      background context. These provide AI context but do NOT appear in sources.
  """
  def ask(user_message, mentioned_contacts, conversation_history, mentioned_meetings \\ [], opts \\ []) do
    pronoun_contacts = Keyword.get(opts, :pronoun_contacts, [])
    context_meetings = Keyword.get(opts, :context_meetings, [])

    # Fetch full contact data from CRMs for explicitly mentioned contacts
    {contact_context, sources} = fetch_contact_context(mentioned_contacts)

    # Fetch context for pronoun-resolution contacts (no sources generated)
    {pronoun_context, _ignored_sources} = fetch_contact_context(pronoun_contacts)

    # Fetch meeting context for explicitly mentioned meetings
    {meeting_context, meeting_sources} = fetch_meeting_context(mentioned_meetings)

    # Fetch context for fallback meetings (no sources generated)
    {context_meeting_text, _ignored_meeting_sources} = fetch_meeting_context(context_meetings)

    # Combine both contact contexts for the AI prompt
    full_contact_context =
      [contact_context, pronoun_context]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    # Combine both meeting contexts for the AI prompt
    full_meeting_context =
      [meeting_context, context_meeting_text]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    prompt = build_prompt(user_message, full_contact_context, full_meeting_context, conversation_history)

    case GeminiClient.generate(prompt) do
      {:ok, response_text} ->
        # Only explicitly added contacts and meetings appear in sources
        {:ok, response_text, sources ++ meeting_sources}

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

  defp fetch_meeting_context(mentioned_meetings) when is_list(mentioned_meetings) and mentioned_meetings != [] do
    meeting_texts =
      mentioned_meetings
      |> Enum.map(fn meeting_ref ->
        meeting_id = Map.get(meeting_ref, :id, Map.get(meeting_ref, "id"))

        case Meetings.get_meeting_with_details(meeting_id) do
          nil ->
            nil

          meeting ->
            case Meetings.generate_prompt_for_meeting(meeting) do
              {:ok, prompt_text} -> prompt_text
              {:error, _} -> format_basic_meeting(meeting)
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    sources =
      mentioned_meetings
      |> Enum.map(fn meeting_ref ->
        %{
          provider: :meeting,
          name: Map.get(meeting_ref, :title, Map.get(meeting_ref, "title", "Meeting"))
        }
      end)

    {Enum.join(meeting_texts, "\n\n"), sources}
  end

  defp fetch_meeting_context(_), do: {"", []}

  defp format_basic_meeting(meeting) do
    """
    [Meeting]
      - Title: #{meeting.title}
      - Recorded at: #{meeting.recorded_at}
      - Duration: #{meeting.duration_seconds} seconds
    """
  end

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

  defp build_prompt(user_message, contact_context, meeting_context, conversation_history) do
    history_text =
      conversation_history
      |> Enum.map(fn msg ->
        role = Map.get(msg, :role, Map.get(msg, "role", "user"))
        content = Map.get(msg, :content, Map.get(msg, "content", ""))
        "#{String.capitalize(role)}: #{content}"
      end)
      |> Enum.join("\n")

    """
    You are a helpful CRM assistant for a business professional. You help answer questions about their contacts, CRM data, and meetings.

    Be concise, professional, and helpful. If you have contact data or meeting data available, reference it specifically. If you don't have enough information to answer a question, say so clearly.

    #{if contact_context != "" do
      """
      CONTACT DATA:
      #{contact_context}
      """
    else
      ""
    end}

    #{if meeting_context != "" do
      """
      MEETING DATA:
      #{meeting_context}
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
