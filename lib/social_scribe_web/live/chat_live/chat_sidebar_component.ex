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
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full" id={"chat-sidebar-#{@id}"}>
      <%!-- Header --%>
      <div class="flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-white">
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
      <div class="flex items-center border-b border-gray-200 bg-white px-2">
        <button
          phx-click="switch_tab"
          phx-value-tab="chat"
          phx-target={@myself}
          class={[
            "px-3 py-2 text-sm font-medium border-b-2 transition-colors",
            @active_tab == :chat && "border-indigo-600 text-indigo-600",
            @active_tab != :chat && "border-transparent text-gray-500 hover:text-gray-700"
          ]}
        >
          Chat
        </button>
        <button
          phx-click="switch_tab"
          phx-value-tab="history"
          phx-target={@myself}
          class={[
            "px-3 py-2 text-sm font-medium border-b-2 transition-colors",
            @active_tab == :history && "border-indigo-600 text-indigo-600",
            @active_tab != :history && "border-transparent text-gray-500 hover:text-gray-700"
          ]}
        >
          History
        </button>
        <div class="flex-1"></div>
        <button
          phx-click="new_conversation"
          phx-target={@myself}
          class="p-1.5 text-gray-400 hover:text-indigo-600 transition-colors"
          title="New conversation"
        >
          <.icon name="hero-plus" class="size-4" />
        </button>
      </div>

      <%!-- Content --%>
      <%= if @active_tab == :chat do %>
        <%!-- Messages area --%>
        <div
          class="flex-1 overflow-y-auto px-4 py-3 space-y-1"
          id="chat-messages-scroll"
          phx-hook="ChatScroll"
        >
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

        <%!-- Input area --%>
        <div class="border-t border-gray-200 bg-white p-3">
          <%!-- Mention dropdown --%>
          <div :if={@mention_query != nil} class="relative">
            <.mention_dropdown
              results={@mention_results}
              searching={@searching_contacts}
              target={@myself}
            />
          </div>

          <form phx-submit="send_message" phx-target={@myself} class="flex items-end gap-2">
            <div class="flex-1 relative">
              <div
                id="chat-mention-input"
                phx-hook="MentionInput"
                phx-target={@myself}
                contenteditable="true"
                data-placeholder="Ask about a contact..."
                class="min-h-[40px] max-h-[120px] overflow-y-auto px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent empty:before:content-[attr(data-placeholder)] empty:before:text-gray-400"
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
            </div>
            <button
              type="submit"
              disabled={@sending}
              class="w-9 h-9 rounded-lg bg-indigo-600 text-white flex items-center justify-center hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex-shrink-0"
            >
              <.icon name="hero-arrow-up" class="size-4" />
            </button>
          </form>

          <%!-- Source icons for mentioned contacts --%>
          <div :if={@mentioned_contacts != []} class="mt-2 flex items-center gap-2">
            <span class="text-xs text-gray-400">Context:</span>
            <.source_icons contacts={@mentioned_contacts} />
            <span class="text-xs text-gray-500">
              {length(@mentioned_contacts)} contact(s) referenced
            </span>
          </div>
        </div>
      <% else %>
        <%!-- History tab --%>
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
    socket =
      socket
      |> assign(:mention_query, query)
      |> assign(:searching_contacts, true)

    send(self(), {:chat_contact_search, query, socket.assigns.current_user.id})
    {:noreply, socket}
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
