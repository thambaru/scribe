defmodule SocialScribeWeb.ChatLive.ChatSidebarComponent do
  @moduledoc """
  LiveComponent for the Ask Anything chat sidebar.
  Handles chat UI state, mentions, and message display.
  """
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ChatComponents

  alias SocialScribe.Chat

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:active_tab, :chat)
      |> assign(:mention_query, nil)
      |> assign(:mention_results, [])
      |> assign(:mentioned_contacts, [])
      |> assign(:searching_contacts, false)
      |> assign(:sending, false)
      |> assign(:conversations, [])
      |> assign(:current_conversation, nil)

    {:ok, socket}
  end

  @impl true
  def update(%{current_user: user} = assigns, socket) do
    socket = assign(socket, :current_user, user)
    socket = assign(socket, :id, assigns.id)

    # Merge incoming assigns (from send_update)
    socket =
      assigns
      |> Map.drop([:current_user, :id, :__changed__])
      |> Enum.reduce(socket, fn {key, val}, acc -> assign(acc, key, val) end)

    # Initialize conversation on first load
    socket =
      if is_nil(socket.assigns.current_conversation) do
        case Chat.get_or_create_active_conversation(user.id) do
          {:ok, conversation} ->
            socket
            |> assign(:current_conversation, conversation)
            |> assign(:messages, conversation.messages || [])

          _ ->
            socket
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Fallback clause for updates without current_user
    socket =
      assigns
      |> Map.drop([:__changed__])
      |> Enum.reduce(socket, fn {key, val}, acc -> assign(acc, key, val) end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full" id={"chat-sidebar-#{@id}"}>
      <%!-- Header --%>
      <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100 bg-white">
        <h2 class="text-lg font-semibold text-gray-900">Ask Anything</h2>
        <button
          phx-click="toggle_chat_sidebar"
          class="text-gray-400 hover:text-gray-600 p-1"
          aria-label="Close sidebar"
        >
          <.icon name="hero-chevron-double-right" class="size-5" />
        </button>
      </div>

      <%!-- Tabs --%>
      <div class="flex items-center gap-2 px-4 py-2 border-b border-gray-100 bg-white">
        <button
          phx-click="switch_tab"
          phx-value-tab="chat"
          phx-target={@myself}
          class={[
            "px-3 py-1.5 text-sm font-medium rounded-full transition-colors",
            @active_tab == :chat && "bg-gray-100 text-gray-900",
            @active_tab != :chat && "text-gray-500 hover:text-gray-700"
          ]}
        >
          Chat
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="history"
          phx-target={@myself}
          class={[
            "px-3 py-1.5 text-sm font-medium rounded-full transition-colors",
            @active_tab == :history && "bg-gray-100 text-gray-900",
            @active_tab != :history && "text-gray-500 hover:text-gray-700"
          ]}
        >
          History
        </button>
        <div class="flex-1"></div>
        <button
          phx-click="new_conversation"
          phx-target={@myself}
          class="p-1.5 text-gray-400 hover:text-gray-600 transition-colors"
          title="New conversation"
        >
          <.icon name="hero-plus" class="size-4" />
        </button>
      </div>

      <%!-- Content --%>
      <%= if @active_tab == :chat do %>
        <div class="flex-1 flex flex-col min-h-0">
          <div class="flex-1 overflow-y-auto space-y-2 px-4 py-3" id="chat-messages-scroll" phx-hook="ChatScroll">
            <div :if={@messages == []} class="flex items-center justify-center h-full">
              <div class="text-center text-gray-400">
                <.icon name="hero-chat-bubble-left-right" class="size-10 mx-auto mb-2" />
                <p class="text-sm">Ask anything about your CRM contacts</p>
                <p class="text-xs mt-1">Use @mention to reference contacts</p>
              </div>
            </div>

            <div :for={message <- @messages}>
              <.chat_message_bubble
                role={message.role}
                content={message.content}
                mentioned_contacts={message.mentioned_contacts || []}
                sources={format_sources(message.sources || [])}
              />
            </div>

            <div :if={@sending} class="flex justify-start mb-3">
              <div class="bg-gray-100 rounded-2xl rounded-bl-md px-4 py-2.5 text-sm text-gray-500">
                <div class="flex items-center gap-2">
                  <div class="animate-pulse flex gap-1">
                    <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce"></div>
                    <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.1s]">
                    </div>
                    <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.2s]">
                    </div>
                  </div>
                  <span>Thinking...</span>
                </div>
              </div>
            </div>
          </div>

          <div class="shrink-0 mx-4 mb-3 mt-2 rounded-2xl border border-[#5689bd] bg-white p-3 shadow-[0_12px_24px_rgba(59,130,246,0.12)]">
            <div class="flex items-center justify-between mb-2">
              <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-md border border-gray-300 bg-white-100 px-3 py-1 text-xs font-medium text-gray-500"
              >
                <.icon name="hero-at-symbol" class="size-3" />
                Add context
              </button>
            </div>

            <div class="relative">
              <div :if={@mention_query != nil} class="relative">
                <.mention_dropdown
                  results={@mention_results}
                  searching={@searching_contacts}
                  target={@myself}
                />
              </div>

              <form phx-submit="send_message" phx-target={@myself} class="space-y-2">
                <div
                  id="chat-mention-input"
                  phx-hook="MentionInput"
                  phx-target={@myself}
                  phx-update="ignore"
                  contenteditable="true"
                  data-placeholder="Ask anything about your meetings"
                  class="chat-mention-input min-h-[72px] max-h-[140px] overflow-y-auto text-sm text-gray-700 outline-none"
                  role="textbox"
                >
                </div>
                <input type="hidden" name="message" id="chat-message-hidden" value="" />
                <input
                  type="hidden"
                  name="mentioned_contacts"
                  id="chat-mentions-hidden"
                  value={Jason.encode!(@mentioned_contacts)}
                />

                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2 text-xs text-gray-400">
                    <span>Sources</span>
                    <.source_icons contacts={@mentioned_contacts} />
                  </div>
                  <button
                    id="chat-send-btn"
                    type="submit"
                    disabled={@sending}
                    class="w-9 h-9 rounded-xl bg-[#f0f5f5] text-[#b2b2b2] flex items-center justify-center hover:bg-[#d5e2fb] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                    aria-label="Send message"
                  >
                    <.icon name="hero-arrow-up" class="size-4" />
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      <% else %>
        <div class="flex-1 overflow-y-auto">
          <div :if={@conversations == []} class="flex items-center justify-center h-full">
            <div class="text-center text-gray-400">
              <.icon name="hero-clock" class="size-10 mx-auto mb-2" />
              <p class="text-sm">No conversation history</p>
            </div>
          </div>

          <div :for={conv <- @conversations} class="border-b border-gray-100">
            <div class="flex items-center justify-between px-4 py-3 hover:bg-gray-50 cursor-pointer group">
              <button
                phx-click="select_conversation"
                phx-value-id={conv.id}
                phx-target={@myself}
                class="flex-1 text-left"
              >
                <p class="text-sm font-medium text-gray-900 truncate">
                  {conv.title || "New conversation"}
                </p>
                <p class="text-xs text-gray-500">
                  {Calendar.strftime(conv.updated_at, "%b %d, %Y %I:%M%p")}
                </p>
              </button>
              <button
                phx-click="delete_conversation"
                phx-value-id={conv.id}
                phx-target={@myself}
                data-confirm="Delete this conversation?"
                class="p-1 text-gray-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      if tab == :history do
        conversations = Chat.list_conversations(socket.assigns.current_user.id)
        assign(socket, :conversations, conversations)
      else
        socket
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("mention_search", %{"query" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket =
        socket
        |> assign(:mention_query, query)
        |> assign(:searching_contacts, true)

      send(self(), {:chat_contact_search, query, socket.assigns.current_user.id})
      {:noreply, socket}
    else
      {:noreply, assign(socket, :mention_query, query)}
    end
  end

  @impl true
  def handle_event("close_mention_dropdown", _params, socket) do
    socket =
      socket
      |> assign(:mention_query, nil)
      |> assign(:mention_results, [])
      |> assign(:searching_contacts, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_mention", params, socket) do
    contact = %{
      id: params["id"],
      provider: params["provider"],
      firstname: params["firstname"],
      lastname: params["lastname"],
      email: params["email"],
      credential_id: params["credential_id"]
    }

    mentioned = socket.assigns.mentioned_contacts ++ [contact]

    socket =
      socket
      |> assign(:mentioned_contacts, mentioned)
      |> assign(:mention_query, nil)
      |> assign(:mention_results, [])
      |> assign(:searching_contacts, false)
      |> push_event("insert_mention_pill", %{
        firstname: contact.firstname,
        provider: contact.provider
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_mention", %{"firstname" => firstname, "provider" => provider}, socket) do
    mentioned =
      Enum.reject(socket.assigns.mentioned_contacts, fn contact ->
        # Match on firstname and provider (handle both string and atom)
        provider_match =
          to_string(contact.provider) == to_string(provider)

        contact.firstname == firstname && provider_match
      end)

    {:noreply, assign(socket, :mentioned_contacts, mentioned)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message} = params, socket)
      when is_binary(message) and byte_size(message) > 0 do
    conversation = socket.assigns.current_conversation
    mentioned = parse_mentioned_contacts(params["mentioned_contacts"])

    # Create user message
    {:ok, user_msg} =
      Chat.add_message(conversation.id, %{
        role: "user",
        content: message,
        mentioned_contacts: mentioned
      })

    # Auto-set title from first message
    Chat.maybe_set_title(conversation, message)

    messages = socket.assigns.messages ++ [user_msg]

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:sending, true)
      |> assign(:mentioned_contacts, [])
      |> push_event("clear_chat_input", %{})

    # Ask parent to run AI query
    send(self(), {:chat_ask_ai, message, mentioned, conversation.id})

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:ok, conversation} = Chat.create_conversation(socket.assigns.current_user.id)

    socket =
      socket
      |> assign(:current_conversation, conversation)
      |> assign(:messages, [])
      |> assign(:mentioned_contacts, [])
      |> assign(:active_tab, :chat)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    conversation = Chat.get_conversation!(id)

    socket =
      socket
      |> assign(:current_conversation, conversation)
      |> assign(:messages, conversation.messages)
      |> assign(:active_tab, :chat)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    Chat.delete_conversation(id)

    conversations = Chat.list_conversations(socket.assigns.current_user.id)

    socket =
      if socket.assigns.current_conversation &&
           to_string(socket.assigns.current_conversation.id) == id do
        case List.first(conversations) do
          nil ->
            {:ok, new_conv} = Chat.create_conversation(socket.assigns.current_user.id)

            socket
            |> assign(:current_conversation, new_conv)
            |> assign(:messages, [])

          conv ->
            socket
            |> assign(:current_conversation, conv)
            |> assign(:messages, conv.messages || [])
        end
      else
        socket
      end

    {:noreply, assign(socket, :conversations, conversations)}
  end

  # Helpers

  defp parse_mentioned_contacts(nil), do: []
  defp parse_mentioned_contacts(""), do: []

  defp parse_mentioned_contacts(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, contacts} when is_list(contacts) -> contacts
      _ -> []
    end
  end

  defp parse_mentioned_contacts(contacts) when is_list(contacts), do: contacts

  defp format_sources(sources) when is_list(sources) do
    Enum.map(sources, fn
      %{provider: p, name: n} ->
        %{provider: p, name: n}

      %{"provider" => p, "name" => n} ->
        %{provider: String.to_existing_atom(p), name: n}

      s ->
        s
    end)
  end

  defp format_sources(_), do: []
end
