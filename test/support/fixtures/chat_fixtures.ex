defmodule SocialScribe.ChatFixtures do
  @moduledoc """
  Test helpers for creating chat entities
  (conversations and messages) via the `SocialScribe.Chat` context.
  """

  alias SocialScribe.Chat

  @doc """
  Creates a conversation for the given user.
  """
  def conversation_fixture(user_id, attrs \\ %{}) do
    {:ok, conversation} = Chat.create_conversation(user_id, attrs)
    conversation
  end

  @doc """
  Adds a message to a conversation.
  Returns the message.
  """
  def message_fixture(conversation_id, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{role: "user", content: "Hello, test message"},
        attrs
      )

    {:ok, message} = Chat.add_message(conversation_id, attrs)
    message
  end

  @doc """
  Creates a conversation with a sequence of messages.
  Returns `{conversation, messages}`.
  """
  def conversation_with_messages_fixture(user_id, message_attrs_list) do
    conversation = conversation_fixture(user_id)

    messages =
      Enum.map(message_attrs_list, fn attrs ->
        message_fixture(conversation.id, attrs)
      end)

    {Chat.get_conversation!(conversation.id), messages}
  end
end
