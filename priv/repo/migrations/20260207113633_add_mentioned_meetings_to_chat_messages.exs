defmodule SocialScribe.Repo.Migrations.AddMentionedMeetingsToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add :mentioned_meetings, :jsonb, default: "[]"
    end
  end
end
