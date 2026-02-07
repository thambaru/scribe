defmodule SocialScribe.Chat.MeetingSearch do
  @moduledoc """
  Searches the user's meetings from the local database.
  Provides searchable, paginated results for the chat context picker.
  """

  alias SocialScribe.Meetings

  @page_size 10

  @doc """
  Searches meetings by title for a user. Returns `{:ok, results, has_more?}`.

  Each result has the shape:
    %{id: integer, title: string, recorded_at: datetime, duration_seconds: integer, participant_count: integer}
  """
  def search(user_id, query, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    offset = page * @page_size

    {meetings, has_more} = Meetings.search_user_meetings(user_id, query, @page_size, offset)
    {:ok, format_results(meetings), has_more}
  end

  @doc """
  Lists recent meetings for a user (for initial display). Returns `{:ok, results, has_more?}`.
  """
  def list_recent(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    offset = page * @page_size

    {meetings, has_more} = Meetings.list_recent_user_meetings(user_id, @page_size, offset)
    {:ok, format_results(meetings), has_more}
  end

  defp format_results(meetings) do
    Enum.map(meetings, fn meeting ->
      %{
        id: meeting.id,
        title: meeting.title,
        recorded_at: meeting.recorded_at,
        duration_seconds: meeting.duration_seconds,
        participant_count: length(meeting.meeting_participants)
      }
    end)
  end
end
