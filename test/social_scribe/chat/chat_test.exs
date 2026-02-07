defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat
  alias SocialScribe.Chat.{Conversation, Message}

  import SocialScribe.AccountsFixtures
  import SocialScribe.ChatFixtures

  describe "list_conversations/1" do
    test "returns conversations for the given user ordered by most recent" do
      user = user_fixture()
      conv1 = conversation_fixture(user.id, %{title: "First"})
      _conv2 = conversation_fixture(user.id, %{title: "Second"})

      # Touch conv1 so it has the latest updated_at
      Process.sleep(1100)
      Chat.add_message(conv1.id, %{role: "user", content: "bump"})

      conversations = Chat.list_conversations(user.id)

      assert length(conversations) == 2
      titles = Enum.map(conversations, & &1.title)
      # conv1 was updated more recently due to add_message, so it should appear first
      assert hd(titles) == "First"
    end

    test "returns empty list for user with no conversations" do
      user = user_fixture()
      assert Chat.list_conversations(user.id) == []
    end

    test "does not return conversations from other users" do
      user1 = user_fixture()
      user2 = user_fixture()
      conversation_fixture(user1.id, %{title: "User1 chat"})

      assert Chat.list_conversations(user2.id) == []
    end

    test "preloads messages for each conversation" do
      user = user_fixture()
      conv = conversation_fixture(user.id)
      message_fixture(conv.id, %{role: "user", content: "Hello"})

      [conversation] = Chat.list_conversations(user.id)
      assert length(conversation.messages) == 1
      assert hd(conversation.messages).content == "Hello"
    end
  end

  describe "get_conversation!/1" do
    test "returns conversation with preloaded messages" do
      user = user_fixture()
      conv = conversation_fixture(user.id, %{title: "Test"})
      message_fixture(conv.id, %{role: "user", content: "First"})
      message_fixture(conv.id, %{role: "assistant", content: "Second"})

      result = Chat.get_conversation!(conv.id)

      assert result.id == conv.id
      assert result.title == "Test"
      assert length(result.messages) == 2
    end

    test "messages are ordered by inserted_at ascending" do
      user = user_fixture()
      conv = conversation_fixture(user.id)
      message_fixture(conv.id, %{role: "user", content: "First"})
      message_fixture(conv.id, %{role: "assistant", content: "Second"})

      result = Chat.get_conversation!(conv.id)
      [first, second] = result.messages

      assert first.content == "First"
      assert second.content == "Second"
    end

    test "raises when conversation does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!(0)
      end
    end
  end

  describe "create_conversation/2" do
    test "creates a conversation with valid user_id" do
      user = user_fixture()

      assert {:ok, %Conversation{} = conversation} = Chat.create_conversation(user.id)
      assert conversation.user_id == user.id
      assert conversation.title == nil
      assert conversation.messages == []
    end

    test "creates a conversation with a title" do
      user = user_fixture()

      assert {:ok, %Conversation{} = conversation} =
               Chat.create_conversation(user.id, %{title: "My Chat"})

      assert conversation.title == "My Chat"
    end

    test "returns error for invalid user_id" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_conversation(0)
    end
  end

  describe "add_message/2" do
    test "adds a user message to a conversation" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      assert {:ok, %Message{} = message} =
               Chat.add_message(conv.id, %{
                 role: "user",
                 content: "Hello!"
               })

      assert message.role == "user"
      assert message.content == "Hello!"
      assert message.conversation_id == conv.id
    end

    test "adds an assistant message with sources" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      sources = [%{provider: "salesforce", name: "John Doe"}]

      assert {:ok, %Message{} = message} =
               Chat.add_message(conv.id, %{
                 role: "assistant",
                 content: "Here is the info.",
                 sources: sources
               })

      assert message.role == "assistant"
      assert message.sources == sources
    end

    test "adds a message with mentioned_contacts" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      contacts = [%{"id" => "123", "provider" => "hubspot", "firstname" => "Jane"}]

      assert {:ok, %Message{} = message} =
               Chat.add_message(conv.id, %{
                 role: "user",
                 content: "What about @Jane?",
                 mentioned_contacts: contacts
               })

      assert message.mentioned_contacts == contacts
    end

    test "touches conversation updated_at" do
      user = user_fixture()
      conv = conversation_fixture(user.id)
      original_updated_at = conv.updated_at

      # Ensure enough time passes for the timestamp to differ
      Process.sleep(1100)

      Chat.add_message(conv.id, %{role: "user", content: "test"})

      updated_conv = Chat.get_conversation!(conv.id)
      assert NaiveDateTime.compare(updated_conv.updated_at, original_updated_at) in [:gt, :eq]
    end

    test "validates required fields" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      assert_raise Ecto.InvalidChangesetError, fn ->
        Chat.add_message(conv.id, %{})
      end
    end

    test "validates role inclusion" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      assert_raise Ecto.InvalidChangesetError, fn ->
        Chat.add_message(conv.id, %{role: "invalid", content: "test"})
      end
    end
  end

  describe "delete_conversation/1" do
    test "deletes a conversation" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      assert {:ok, %Conversation{}} = Chat.delete_conversation(conv.id)

      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_conversation!(conv.id)
      end
    end

    test "deleting a conversation cascades to messages" do
      user = user_fixture()
      conv = conversation_fixture(user.id)
      message_fixture(conv.id, %{role: "user", content: "Hello"})

      Chat.delete_conversation(conv.id)

      assert Repo.all(Message) == []
    end

    test "raises when conversation does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.delete_conversation(0)
      end
    end
  end

  describe "get_or_create_active_conversation/1" do
    test "creates a new conversation when none exist" do
      user = user_fixture()

      assert {:ok, %Conversation{} = conversation} =
               Chat.get_or_create_active_conversation(user.id)

      assert conversation.user_id == user.id
      assert conversation.messages == []
    end

    test "returns existing most recent conversation" do
      user = user_fixture()
      old_conv = conversation_fixture(user.id, %{title: "Old"})
      _new_conv = conversation_fixture(user.id, %{title: "New"})

      # Touch old_conv so it has the latest updated_at and becomes "most recent"
      Process.sleep(1100)
      Chat.add_message(old_conv.id, %{role: "user", content: "bump"})

      assert {:ok, %Conversation{} = conversation} =
               Chat.get_or_create_active_conversation(user.id)

      assert conversation.id == old_conv.id
      assert conversation.title == "Old"
    end

    test "preloads messages on the returned conversation" do
      user = user_fixture()
      conv = conversation_fixture(user.id)
      message_fixture(conv.id, %{role: "user", content: "Hello"})

      assert {:ok, conversation} = Chat.get_or_create_active_conversation(user.id)
      assert length(conversation.messages) == 1
    end
  end

  describe "maybe_set_title/2" do
    test "sets title from first message when conversation has no title" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      assert {:ok, updated} = Chat.maybe_set_title(conv, "What is John's email?")
      assert updated.title == "What is John's email?"
    end

    test "truncates long messages to 50 chars with ellipsis" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      long_message = String.duplicate("a", 60)
      assert {:ok, updated} = Chat.maybe_set_title(conv, long_message)
      assert String.length(updated.title) == 53
      assert String.ends_with?(updated.title, "...")
    end

    test "does not truncate messages of exactly 50 chars" do
      user = user_fixture()
      conv = conversation_fixture(user.id)

      message = String.duplicate("b", 50)
      assert {:ok, updated} = Chat.maybe_set_title(conv, message)
      assert updated.title == message
      refute String.ends_with?(updated.title, "...")
    end

    test "does not update title when conversation already has one" do
      user = user_fixture()
      conv = conversation_fixture(user.id, %{title: "Existing Title"})

      assert {:ok, unchanged} = Chat.maybe_set_title(conv, "New message")
      assert unchanged.title == "Existing Title"
    end
  end

  describe "Conversation changeset" do
    test "valid changeset with user_id" do
      user = user_fixture()
      changeset = Conversation.changeset(%Conversation{}, %{user_id: user.id})
      assert changeset.valid?
    end

    test "invalid without user_id" do
      changeset = Conversation.changeset(%Conversation{}, %{})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts optional title" do
      user = user_fixture()
      changeset = Conversation.changeset(%Conversation{}, %{user_id: user.id, title: "My Chat"})
      assert changeset.valid?
    end
  end

  describe "Message changeset" do
    test "valid changeset with required fields" do
      changeset =
        Message.changeset(%Message{}, %{
          conversation_id: 1,
          role: "user",
          content: "Hello"
        })

      assert changeset.valid?
    end

    test "invalid without conversation_id" do
      changeset = Message.changeset(%Message{}, %{role: "user", content: "Hello"})
      refute changeset.valid?
      assert %{conversation_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without role" do
      changeset = Message.changeset(%Message{}, %{conversation_id: 1, content: "Hello"})
      refute changeset.valid?
      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without content" do
      changeset = Message.changeset(%Message{}, %{conversation_id: 1, role: "user"})
      refute changeset.valid?
      assert %{content: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates role inclusion" do
      changeset =
        Message.changeset(%Message{}, %{
          conversation_id: 1,
          role: "invalid_role",
          content: "Hello"
        })

      refute changeset.valid?
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts valid roles" do
      for role <- ["user", "assistant", "system"] do
        changeset =
          Message.changeset(%Message{}, %{
            conversation_id: 1,
            role: role,
            content: "Hello"
          })

        assert changeset.valid?, "Expected role '#{role}' to be valid"
      end
    end

    test "defaults mentioned_contacts to empty list" do
      changeset =
        Message.changeset(%Message{}, %{
          conversation_id: 1,
          role: "user",
          content: "Hello"
        })

      assert changeset.valid?
    end

    test "defaults sources to empty list" do
      changeset =
        Message.changeset(%Message{}, %{
          conversation_id: 1,
          role: "assistant",
          content: "Response"
        })

      assert changeset.valid?
    end
  end
end
