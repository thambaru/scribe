defmodule SocialScribe.Chat do
  @moduledoc """
  The Chat context. Manages chat conversations and messages
  for the Ask Anything CRM chat sidebar.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Chat.{Conversation, Message}

  @doc """
  Lists all conversations for a user, ordered by most recently updated.
  """
  def list_conversations(user_id) do
    from(c in Conversation,
      where: c.user_id == ^user_id,
      order_by: [desc: c.updated_at],
      preload: [:messages]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single conversation with preloaded messages.
  Raises if not found.
  """
  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in Message, order_by: [asc: m.inserted_at]))
  end

  @doc """
  Creates a new conversation for a user.
  """
  def create_conversation(user_id, attrs \\ %{}) do
    case %Conversation{}
         |> Conversation.changeset(Map.put(attrs, :user_id, user_id))
         |> Repo.insert() do
      {:ok, conversation} ->
        {:ok, %{conversation | messages: []}}

      error ->
        error
    end
  end

  @doc """
  Adds a message to a conversation. Also touches the conversation's updated_at.
  """
  def add_message(conversation_id, attrs) do
    Repo.transaction(fn ->
      message =
        %Message{}
        |> Message.changeset(Map.put(attrs, :conversation_id, conversation_id))
        |> Repo.insert!()

      # Touch conversation updated_at
      from(c in Conversation, where: c.id == ^conversation_id)
      |> Repo.update_all(set: [updated_at: NaiveDateTime.utc_now()])

      message
    end)
  end

  @doc """
  Deletes a conversation and all its messages.
  """
  def delete_conversation(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.delete()
  end

  @doc """
  Gets the most recent conversation for a user, or creates a new one.
  """
  def get_or_create_active_conversation(user_id) do
    query =
      from(c in Conversation,
        where: c.user_id == ^user_id,
        order_by: [desc: c.updated_at],
        limit: 1,
        preload: [messages: ^from(m in Message, order_by: [asc: m.inserted_at])]
      )

    case Repo.one(query) do
      nil -> create_conversation(user_id)
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Auto-generates a title from the first user message if the conversation has no title.
  """
  def maybe_set_title(%Conversation{title: nil} = conversation, message_content) do
    title =
      message_content
      |> String.slice(0, 50)
      |> then(fn t -> if String.length(message_content) > 50, do: t <> "...", else: t end)

    conversation
    |> Conversation.changeset(%{title: title})
    |> Repo.update()
  end

  def maybe_set_title(conversation, _message_content), do: {:ok, conversation}
end
