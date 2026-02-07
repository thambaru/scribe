defmodule SocialScribe.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.Conversation

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :mentioned_contacts, {:array, :map}, default: []
    field :mentioned_meetings, {:array, :map}, default: []
    field :sources, {:array, :map}, default: []

    belongs_to :conversation, Conversation

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :mentioned_contacts, :mentioned_meetings, :sources])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
    |> foreign_key_constraint(:conversation_id)
  end
end
