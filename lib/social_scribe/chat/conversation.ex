defmodule SocialScribe.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.Message

  schema "chat_conversations" do
    field :title, :string

    belongs_to :user, User
    has_many :messages, Message

    timestamps()
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:user_id, :title])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
  end
end
