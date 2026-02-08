defmodule SocialScribe.Chat.MeetingSearchTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat.MeetingSearch

  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures

  defp create_meeting_for_user(user, attrs) do
    calendar_event = calendar_event_fixture(%{user_id: user.id})

    meeting =
      meeting_fixture(
        Map.merge(
          %{calendar_event_id: calendar_event.id, title: "Team Standup"},
          attrs
        )
      )

    meeting
  end

  describe "search/3" do
    test "returns matching meetings by title" do
      user = user_fixture()
      _meeting = create_meeting_for_user(user, %{title: "Weekly Standup"})

      assert {:ok, results, _has_more} = MeetingSearch.search(user.id, "Standup")
      assert length(results) == 1
      assert hd(results).title == "Weekly Standup"
    end

    test "returns empty list when no meetings match" do
      user = user_fixture()
      _meeting = create_meeting_for_user(user, %{title: "Weekly Standup"})

      assert {:ok, [], false} = MeetingSearch.search(user.id, "Nonexistent")
    end

    test "does not return meetings from other users" do
      user1 = user_fixture()
      user2 = user_fixture()
      _meeting = create_meeting_for_user(user1, %{title: "User1 Meeting"})

      assert {:ok, [], false} = MeetingSearch.search(user2.id, "User1")
    end

    test "results include correct shape" do
      user = user_fixture()
      _meeting = create_meeting_for_user(user, %{title: "Design Review", duration_seconds: 3600})

      assert {:ok, [result], _has_more} = MeetingSearch.search(user.id, "Design")
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :title)
      assert Map.has_key?(result, :recorded_at)
      assert Map.has_key?(result, :duration_seconds)
      assert Map.has_key?(result, :participant_count)
    end

    test "returns participant_count from meeting_participants" do
      user = user_fixture()
      meeting = create_meeting_for_user(user, %{title: "Big Meeting"})

      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Alice"})
      meeting_participant_fixture(%{meeting_id: meeting.id, name: "Bob"})

      assert {:ok, [result], _has_more} = MeetingSearch.search(user.id, "Big")
      assert result.participant_count == 2
    end

    test "supports pagination via page option" do
      user = user_fixture()

      # Create 12 meetings to exceed default page size of 10
      for i <- 1..12 do
        create_meeting_for_user(user, %{
          title: "Meeting #{String.pad_leading(to_string(i), 2, "0")}"
        })
      end

      assert {:ok, page0_results, true} = MeetingSearch.search(user.id, "Meeting", page: 0)
      assert length(page0_results) == 10

      assert {:ok, page1_results, false} = MeetingSearch.search(user.id, "Meeting", page: 1)
      assert length(page1_results) == 2
    end

    test "has_more is false when results fit in one page" do
      user = user_fixture()
      create_meeting_for_user(user, %{title: "Only Meeting"})

      assert {:ok, _results, false} = MeetingSearch.search(user.id, "Only")
    end

    test "search is case-insensitive" do
      user = user_fixture()
      _meeting = create_meeting_for_user(user, %{title: "QUARTERLY Review"})

      assert {:ok, results, _has_more} = MeetingSearch.search(user.id, "quarterly")
      assert length(results) == 1
    end
  end

  describe "list_recent/2" do
    test "returns recent meetings for a user" do
      user = user_fixture()
      _meeting = create_meeting_for_user(user, %{title: "Recent Meeting"})

      assert {:ok, results, _has_more} = MeetingSearch.list_recent(user.id)
      assert length(results) == 1
      assert hd(results).title == "Recent Meeting"
    end

    test "returns empty list when user has no meetings" do
      user = user_fixture()

      assert {:ok, [], false} = MeetingSearch.list_recent(user.id)
    end

    test "does not return meetings from other users" do
      user1 = user_fixture()
      user2 = user_fixture()
      _meeting = create_meeting_for_user(user1, %{title: "User1 Only"})

      assert {:ok, [], false} = MeetingSearch.list_recent(user2.id)
    end

    test "supports pagination via page option" do
      user = user_fixture()

      for i <- 1..12 do
        create_meeting_for_user(user, %{
          title: "Meeting #{String.pad_leading(to_string(i), 2, "0")}"
        })
      end

      assert {:ok, page0_results, true} = MeetingSearch.list_recent(user.id, page: 0)
      assert length(page0_results) == 10

      assert {:ok, page1_results, false} = MeetingSearch.list_recent(user.id, page: 1)
      assert length(page1_results) == 2
    end

    test "has_more is false when results fit in one page" do
      user = user_fixture()
      create_meeting_for_user(user, %{title: "Solo Meeting"})

      assert {:ok, _results, false} = MeetingSearch.list_recent(user.id)
    end

    test "results include correct shape" do
      user = user_fixture()
      _meeting = create_meeting_for_user(user, %{title: "Formatted Meeting"})

      assert {:ok, [result], _has_more} = MeetingSearch.list_recent(user.id)
      assert Map.has_key?(result, :id)
      assert Map.has_key?(result, :title)
      assert Map.has_key?(result, :recorded_at)
      assert Map.has_key?(result, :duration_seconds)
      assert Map.has_key?(result, :participant_count)
    end
  end
end
