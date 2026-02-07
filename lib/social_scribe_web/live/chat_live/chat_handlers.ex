defmodule SocialScribeWeb.ChatLive.ChatHandlers do
  @moduledoc """
  Shared chat event handlers injected into dashboard LiveViews via `use`.
  Uses @before_compile to ensure these handlers are added after
  the module's own handlers, preventing function clause conflicts.
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile SocialScribeWeb.ChatLive.ChatHandlers
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def handle_info({:chat_contact_search, query, user_id}, socket) do
        {:ok, results} = SocialScribe.Chat.ContactSearch.search(user_id, query)

        send_update(SocialScribeWeb.ChatLive.ChatSidebarComponent,
          id: "chat-sidebar",
          mention_results: results,
          searching_contacts: false
        )

        {:noreply, socket}
      end

      def handle_info(
            {:chat_ask_ai, message, mentioned_contacts, conversation_id},
            socket
          ) do
        conversation = SocialScribe.Chat.get_conversation!(conversation_id)
        history = Enum.map(conversation.messages, &Map.take(&1, [:role, :content]))

        mentioned_contacts =
          if mentioned_contacts == [] do
            fallback_mentioned_contacts(conversation.messages)
          else
            mentioned_contacts
          end

        case SocialScribe.Chat.ChatAi.ask(message, mentioned_contacts, history) do
          {:ok, response_text, sources} ->
            SocialScribe.Chat.add_message(conversation_id, %{
              role: "assistant",
              content: response_text,
              sources: sources
            })

            updated_conversation = SocialScribe.Chat.get_conversation!(conversation_id)

            send_update(SocialScribeWeb.ChatLive.ChatSidebarComponent,
              id: "chat-sidebar",
              messages: updated_conversation.messages,
              sending: false
            )

          {:error, _reason} ->
            SocialScribe.Chat.add_message(conversation_id, %{
              role: "assistant",
              content:
                "I'm sorry, I encountered an error processing your request. Please try again."
            })

            updated_conversation = SocialScribe.Chat.get_conversation!(conversation_id)

            send_update(SocialScribeWeb.ChatLive.ChatSidebarComponent,
              id: "chat-sidebar",
              messages: updated_conversation.messages,
              sending: false
            )
        end

        {:noreply, socket}
      end

      defp fallback_mentioned_contacts(messages) do
        messages
        |> Enum.reverse()
        |> Enum.find_value([], fn msg ->
          if Map.get(msg, :role) == "user" do
            contacts = Map.get(msg, :mentioned_contacts, [])
            if contacts != [], do: contacts, else: nil
          end
        end)
      end

      def handle_event("toggle_chat_sidebar", _params, socket) do
        {:noreply, assign(socket, :chat_open, !socket.assigns.chat_open)}
      end

      def handle_info(_chat_unhandled_msg, socket) do
        {:noreply, socket}
      end
    end
  end
end
