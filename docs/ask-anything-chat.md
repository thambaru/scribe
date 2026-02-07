# Ask Anything Chat

Technical documentation for the Ask Anything chat sidebar in SocialScribe. This feature provides a conversational AI assistant that lets users ask questions about their CRM contacts and meetings using natural language, with `@mention` support for contacts and meeting context selection.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [File Map](#file-map)
- [Database Schema](#database-schema)
- [Backend Services](#backend-services)
- [LiveView Component](#liveview-component)
- [ChatHandlers Macro](#chathandlers-macro)
- [JavaScript Hooks](#javascript-hooks)
- [Function Components](#function-components)
- [Layout Integration](#layout-integration)
- [End-to-End Data Flows](#end-to-end-data-flows)
- [Error Handling and Resilience](#error-handling-and-resilience)
- [Key Design Decisions](#key-design-decisions)
- [Extending the Feature](#extending-the-feature)

---

## Architecture Overview

```
User types in chat input
       |
       +--> MentionInput JS Hook (contenteditable, @mention detection)
       |         |
       |         +--> "mention_search" event --> ChatSidebarComponent
       |                                             |
       |                                    send {:chat_contact_search}
       |                                             |
       |                                      Parent LiveView
       |                                      (ChatHandlers)
       |                                             |
       |                                      ContactSearch
       |                                      /            \
       |                               HubSpot API    Salesforce API
       |                                (parallel Task.async)
       |
       +--> "send_message" event --> ChatSidebarComponent
                                          |
                                   Persist user msg (Chat context)
                                   send {:chat_ask_ai}
                                          |
                                   Parent LiveView (ChatHandlers)
                                          |
                                       ChatAi.ask/4
                                      /     |      \
                              CRM APIs  Meetings  GeminiClient
                              (parallel)  context   (LLM call)
                                          |
                                   Persist AI msg (Chat context)
                                   send_update back to ChatSidebarComponent
```

The sidebar is rendered in the dashboard layout and available on every authenticated page. Communication between the `ChatSidebarComponent` (LiveComponent) and the parent LiveView happens via `send/2` (component to parent) and `send_update/2` (parent to component).

---

## File Map

### Database

| File | Purpose |
|------|---------|
| `priv/repo/migrations/20260207005948_create_chat_tables.exs` | Creates `chat_conversations` and `chat_messages` tables |
| `priv/repo/migrations/20260207113633_add_mentioned_meetings_to_chat_messages.exs` | Adds `mentioned_meetings` JSONB column |

### Schemas

| File | Purpose |
|------|---------|
| `lib/social_scribe/chat/conversation.ex` | Ecto schema for conversations |
| `lib/social_scribe/chat/message.ex` | Ecto schema for messages |

### Backend Services

| File | Purpose |
|------|---------|
| `lib/social_scribe/chat.ex` | Context module - CRUD for conversations and messages |
| `lib/social_scribe/chat/chat_ai.ex` | AI response generation with CRM + meeting context |
| `lib/social_scribe/chat/contact_search.ex` | Parallel CRM contact search (HubSpot + Salesforce) |
| `lib/social_scribe/chat/meeting_search.ex` | Paginated meeting search from local database |
| `lib/social_scribe/gemini_client.ex` | Shared Google Gemini API client |

### LiveView

| File | Purpose |
|------|---------|
| `lib/social_scribe_web/live/chat_live/chat_sidebar_component.ex` | Main LiveComponent - UI state, events, rendering |
| `lib/social_scribe_web/live/chat_live/chat_handlers.ex` | Macro injecting chat handlers into parent LiveViews |
| `lib/social_scribe_web/components/chat_components.ex` | Stateless function components (bubbles, pills, dropdowns) |

### JavaScript Hooks

| File | Purpose |
|------|---------|
| `assets/js/hooks/mention_input.js` | Contenteditable input with @mention detection and pill insertion |
| `assets/js/hooks/chat_scroll.js` | Auto-scroll messages to bottom on new content |
| `assets/js/hooks/chat_portal.js` | DOM portal to move LiveComponent into sidebar shell |

### Layout & Integration

| File | Purpose |
|------|---------|
| `lib/social_scribe_web/components/layouts/dashboard.html.heex` | Renders sidebar shell + floating button |
| `lib/social_scribe_web/components/layouts.ex` | Imports `ChatComponents` |
| `lib/social_scribe_web/live_hooks.ex` | `attach_chat_sidebar` on_mount hook sets `chat_open: false` |

### LiveViews with Chat Integration

These LiveViews include `use SocialScribeWeb.ChatLive.ChatHandlers`:

- `lib/social_scribe_web/live/home_live.ex`
- `lib/social_scribe_web/live/meeting_live/index.ex`
- `lib/social_scribe_web/live/meeting_live/show.ex`
- `lib/social_scribe_web/live/automation_live/index.ex`
- `lib/social_scribe_web/live/automation_live/show.ex`
- `lib/social_scribe_web/live/user_settings_live.ex`

---

## Database Schema

### `chat_conversations`

```sql
CREATE TABLE chat_conversations (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       varchar(255),                -- Auto-generated from first message (first 50 chars)
  inserted_at timestamp NOT NULL,
  updated_at  timestamp NOT NULL           -- Touched on every new message
);
CREATE INDEX chat_conversations_user_id_index ON chat_conversations(user_id);
```

### `chat_messages`

```sql
CREATE TABLE chat_messages (
  id                  bigserial PRIMARY KEY,
  conversation_id     bigint NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
  role                varchar(255) NOT NULL,  -- "user" | "assistant" | "system"
  content             text NOT NULL,
  mentioned_contacts  jsonb DEFAULT '[]',     -- [{id, provider, firstname, lastname, email, credential_id}]
  mentioned_meetings  jsonb DEFAULT '[]',     -- [{id, title}]
  sources             jsonb DEFAULT '[]',     -- [{provider, name}]
  inserted_at         timestamp NOT NULL,
  updated_at          timestamp NOT NULL
);
CREATE INDEX chat_messages_conversation_id_index ON chat_messages(conversation_id);
```

### Ecto Schemas

**Conversation** (`lib/social_scribe/chat/conversation.ex`):

```elixir
schema "chat_conversations" do
  field :title, :string
  belongs_to :user, User
  has_many :messages, Message
  timestamps()
end
```

**Message** (`lib/social_scribe/chat/message.ex`):

```elixir
schema "chat_messages" do
  field :role, :string                              # validated: "user" | "assistant" | "system"
  field :content, :string
  field :mentioned_contacts, {:array, :map}, default: []
  field :mentioned_meetings, {:array, :map}, default: []
  field :sources, {:array, :map}, default: []
  belongs_to :conversation, Conversation
  timestamps()
end
```

---

## Backend Services

### Chat Context (`lib/social_scribe/chat.ex`)

Manages conversation and message CRUD:

| Function | Description |
|----------|-------------|
| `list_conversations(user_id)` | All conversations for user, ordered by `updated_at` desc, with preloaded messages |
| `get_conversation!(id)` | Single conversation with messages ordered by `inserted_at` asc |
| `create_conversation(user_id, attrs)` | New conversation with empty messages list |
| `get_or_create_active_conversation(user_id)` | Most recent conversation or creates new one |
| `add_message(conversation_id, attrs)` | Insert message in transaction + touch conversation `updated_at` |
| `delete_conversation(id)` | Cascade-deletes conversation and all messages |
| `maybe_set_title(conversation, content)` | Auto-generates title from first 50 chars of first message |

Key detail: `add_message/2` uses `Repo.transaction` to atomically insert the message and update the conversation's `updated_at` timestamp. This ensures the conversation list always reflects the most recent activity.

### Contact Search (`lib/social_scribe/chat/contact_search.ex`)

Searches both HubSpot and Salesforce in parallel:

```elixir
def search(user_id, query)
```

1. Fetches user's HubSpot and Salesforce credentials
2. Creates `Task.async` for each available provider (skips if credential is nil)
3. `Task.await_many(10_000)` - 10-second timeout for parallel execution
4. Flattens, deduplicates, and limits to 10 results
5. Each result is enriched with:
   - `provider` - `:hubspot` or `:salesforce`
   - `credential_id` - needed later to fetch full contact data for AI

If one CRM fails (network error, auth error), its results are silently returned as `[]` and the other CRM's results still appear.

### Meeting Search (`lib/social_scribe/chat/meeting_search.ex`)

Searches the local database (not an external API):

| Function | Description |
|----------|-------------|
| `search(user_id, query, opts)` | Title-based search with pagination |
| `list_recent(user_id, opts)` | Recent meetings without search filter |

- Page size: 10 results
- Returns `{:ok, results, has_more?}` to support "Load more" pagination
- Each result: `%{id, title, recorded_at, duration_seconds, participant_count}`

### ChatAi (`lib/social_scribe/chat/chat_ai.ex`)

Generates AI responses with full CRM and meeting context:

```elixir
def ask(user_message, mentioned_contacts, conversation_history, mentioned_meetings \\ [])
```

**Step 1 - Fetch contact context:**

For each mentioned contact, fetches full details from the appropriate CRM in parallel using `Task.async/await_many(15_000)`:

- Uses `credential_id` to load the `UserCredential`
- Routes to `HubspotApi.get_contact/2` or `SalesforceApi.get_contact/2` based on `provider`
- Formats into text blocks like:
  ```
  [Hubspot Contact]
    - firstname: John
    - email: john@example.com
    - phone: 555-1234
  ```

**Step 2 - Fetch meeting context:**

For each mentioned meeting:
- Loads via `Meetings.get_meeting_with_details(id)`
- Calls `Meetings.generate_prompt_for_meeting(meeting)` to get a rich text representation including the transcript
- Falls back to a basic format (title, date, duration) if prompt generation fails

**Step 3 - Build prompt:**

Constructs a structured prompt with four sections:

```
System instruction: "You are a helpful CRM assistant..."

CONTACT DATA:
[Hubspot Contact]
  - firstname: John
  ...

MEETING DATA:
[Meeting]
  - Title: Q4 Planning
  - Transcript: ...

CONVERSATION HISTORY:
User: previous message
Assistant: previous response

User: current message
```

Sections are conditionally included - if no contacts/meetings/history exist, those sections are omitted entirely.

**Step 4 - Generate response:**

Sends the prompt to `GeminiClient.generate/1` (Google Gemini API, default model: `gemini-2.0-flash-lite`).

**Return value:**

```elixir
{:ok, response_text, sources}
```

Where `sources` is a list of `%{provider: :hubspot | :salesforce | :meeting, name: "Contact Name or Meeting Title"}`.

### Gemini Client (`lib/social_scribe/gemini_client.ex`)

Shared AI client used by both the chat feature and the Salesforce/HubSpot suggestion generators:

- HTTP client: Tesla
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Default model: `gemini-2.0-flash-lite` (configurable via `config :social_scribe, :gemini_model`)
- API key from config: `config :social_scribe, :gemini_api_key`
- Returns `{:ok, text}` or `{:error, reason}`

---

## LiveView Component

### ChatSidebarComponent (`lib/social_scribe_web/live/chat_live/chat_sidebar_component.ex`)

The main LiveComponent managing all chat UI state and user interactions.

### State (Socket Assigns)

| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `messages` | list | `[]` | Current conversation messages |
| `input` | string | `""` | Legacy - JS handles input now |
| `active_tab` | atom | `:chat` | `:chat` or `:history` |
| `sending` | boolean | `false` | Loading state while AI responds |
| `current_conversation` | struct/nil | `nil` | Active conversation |
| `conversations` | list | `[]` | All conversations (history tab) |
| **Contact Mentions** | | | |
| `mention_query` | string/nil | `nil` | Current @query text |
| `mention_results` | list | `[]` | Search results from CRMs |
| `mentioned_contacts` | list | `[]` | Selected contacts |
| `searching_contacts` | boolean | `false` | Search in progress |
| **Meeting Context** | | | |
| `context_menu_open` | boolean | `false` | "Add context" menu visible |
| `context_type` | atom/nil | `nil` | Currently `:meetings` or nil |
| `meeting_search_query` | string | `""` | Meeting search input |
| `meeting_search_results` | list | `[]` | Meeting search results |
| `searching_meetings` | boolean | `false` | Meeting search in progress |
| `mentioned_meetings` | list | `[]` | Selected meetings |
| `meeting_search_page` | integer | `0` | Pagination offset |
| `meeting_has_more` | boolean | `false` | More results available |

### Initialization

On first `update/2` with `current_user`:
- Calls `Chat.get_or_create_active_conversation(user.id)`
- Loads existing messages from the conversation
- On subsequent updates, merges incoming assigns (from `send_update`) into socket

Meeting search results support appending for pagination: when `meeting_search_append: true` is present in the assigns, new results are concatenated to existing ones instead of replacing them.

### Events Handled

| Event | Trigger | Action |
|-------|---------|--------|
| `switch_tab` | Tab button click | Switches to `:chat` or `:history` tab. Loads conversations list when switching to history. |
| `mention_search` | `@query` in input (via JS hook) | Sends `{:chat_contact_search, query, user_id}` to parent when query >= 2 chars |
| `close_mention_dropdown` | Focus leaves mention area | Clears mention state |
| `select_mention` | Click contact in dropdown | Adds to `mentioned_contacts`, pushes `insert_mention_pill` event to JS hook |
| `remove_mention` | Backspace on pill (via JS hook) | Removes contact from `mentioned_contacts` |
| `toggle_context_menu` | "Add context" button | Opens/closes context picker |
| `select_context_type` | Click "Meetings" option | Sets `context_type: :meetings`, sends `{:chat_meeting_list}` to parent |
| `meeting_search` | Text input in meeting dropdown | Sends `{:chat_meeting_search}` or `{:chat_meeting_list}` to parent |
| `select_meeting` | Click meeting in dropdown | Adds to `mentioned_meetings` (prevents duplicates), closes dropdown |
| `remove_meeting` | Click X on meeting pill | Removes from `mentioned_meetings` |
| `load_more_meetings` | "Load more..." button | Increments page, sends search/list request |
| `send_message` | Form submit (Enter key) | Persists user message, sends `{:chat_ask_ai}` to parent, clears input |
| `new_conversation` | "+" button | Creates new conversation, clears messages |
| `select_conversation` | Click conversation in history | Loads conversation and messages, switches to chat tab |
| `delete_conversation` | Trash icon (with confirm dialog) | Deletes conversation, falls back to next or creates new |

### Message Submission Flow

When `send_message` fires:

1. Parse `mentioned_contacts` and `mentioned_meetings` from hidden form fields (JSON strings)
2. `Chat.add_message(conversation.id, %{role: "user", content: message, mentioned_contacts: ..., mentioned_meetings: ...})`
3. `Chat.maybe_set_title(conversation, message)` - auto-titles if first message
4. Append user message to local `messages` list immediately (optimistic UI)
5. Set `sending: true` (shows "Thinking..." animation)
6. Clear `mentioned_contacts` and `mentioned_meetings` lists
7. Push `clear_chat_input` event to JS hook
8. `send(self(), {:chat_ask_ai, message, mentioned, conversation.id, mentioned_meetings})`

---

## ChatHandlers Macro

### Module: `SocialScribeWeb.ChatLive.ChatHandlers`

**File:** `lib/social_scribe_web/live/chat_live/chat_handlers.ex`

A macro that injects chat-related `handle_info/2` and `handle_event/2` handlers into any LiveView. Uses `@before_compile` to ensure these handlers are added **after** the module's own handlers, preventing function clause conflicts.

### Usage

```elixir
defmodule SocialScribeWeb.HomeLive do
  use SocialScribeWeb, :live_view
  use SocialScribeWeb.ChatLive.ChatHandlers
  # ...
end
```

### Injected Handlers

#### `handle_info({:chat_contact_search, query, user_id}, socket)`

1. Calls `ContactSearch.search(user_id, query)`
2. `send_update(ChatSidebarComponent, mention_results: results, searching_contacts: false)`

#### `handle_info({:chat_meeting_search, query, user_id, page}, socket)`

1. Calls `MeetingSearch.search(user_id, query, page: page)`
2. If `page > 0`, includes `meeting_search_append: true` to concatenate results
3. `send_update(ChatSidebarComponent, meeting_search_results: results, ...)`

#### `handle_info({:chat_meeting_list, user_id, page}, socket)`

Same as above but calls `MeetingSearch.list_recent/2` (no query filter).

#### `handle_info({:chat_ask_ai, message, mentioned_contacts, conversation_id, mentioned_meetings}, socket)`

1. Loads full conversation with `Chat.get_conversation!(conversation_id)`
2. Extracts message history as `[%{role, content}]`
3. **Fallback logic:** If `mentioned_contacts` or `mentioned_meetings` are empty, scans conversation history in reverse for the last user message that had mentions. This enables multi-turn conversations where the user references a contact once and then asks follow-up questions without re-mentioning.
4. Calls `ChatAi.ask(message, mentioned_contacts, history, mentioned_meetings)`
5. On success: persists assistant response via `Chat.add_message`, reloads conversation, sends full messages list to component
6. On error: persists a generic error message as the assistant response
7. Always sets `sending: false` on the component

#### `handle_event("toggle_chat_sidebar", _params, socket)`

Toggles `socket.assigns.chat_open` boolean, which controls sidebar visibility in the layout.

#### Catch-all `handle_info`

A final catch-all clause `handle_info(_chat_unhandled_msg, socket)` prevents crashes from unknown messages.

---

## JavaScript Hooks

### MentionInput (`assets/js/hooks/mention_input.js`)

The most complex hook - manages a `contenteditable` div that supports rich text with inline mention pills.

**Lifecycle:**

- `mounted()`: Sets up `input`, `keydown` event listeners + server event handlers

**Input Handling:**

- On every input, checks for `@query` pattern using regex `/@(\S+)$/`
- If query >= 2 chars: saves cursor position and match, fires `mention_search` event to server
- If no `@` pattern: fires `close_mention_dropdown` event

**Key Handling:**

- `Enter` (without Shift): Prevents default, calls `submitMessage()`
- `Shift+Enter`: Allows line break (default behavior)
- `Backspace`: Checks if cursor is immediately after a mention pill. If so, prevents default, removes the pill DOM element, and fires `remove_mention` event to server

**Server Events:**

| Event | Handler |
|-------|---------|
| `insert_mention_pill` | Creates a `<span>` element with avatar initial + CRM icon SVG, replaces the `@query` text in the DOM, positions cursor after pill |
| `clear_chat_input` | Clears the contenteditable innerHTML and updates hidden input |

**Mention Pill DOM Structure:**

```html
<span contenteditable="false" data-mention="true" data-provider="hubspot" data-firstname="John"
      class="inline-flex items-center gap-1 px-1 pr-2 py-0.5 mx-0.5 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium">
  <span style="position:relative;display:inline-flex;">
    <span style="...avatar styles...">J</span>         <!-- Initial -->
    <span style="...badge styles..."><!-- CRM SVG --></span>  <!-- HubSpot/Salesforce icon -->
  </span>
  @John
</span>
```

**Form Submission:**

`submitMessage()` reads the plain text (converting pills back to `@firstname` format), sets the hidden input value, and dispatches a form submit event.

**Helper Methods:**

| Method | Purpose |
|--------|---------|
| `getCursorPosition()` | Calculates cursor offset in the contenteditable using Range API |
| `getPlainText()` | Walks child nodes, converts pills to `@firstname` text, strips `&nbsp;` |
| `updateHiddenInput()` | Syncs hidden `<input>` with current plain text content |
| `updateSendButton()` | Enables/disables send button based on whether input has content |
| `getCrmIconSvg(provider)` | Returns inline SVG string for HubSpot or Salesforce icon |

### ChatScroll (`assets/js/hooks/chat_scroll.js`)

Auto-scrolls the messages container to the bottom whenever content changes.

- `mounted()`: Scrolls to bottom, sets up `MutationObserver` watching `childList` and `subtree`
- `updated()`: Scrolls to bottom
- `destroyed()`: Disconnects observer

### ChatPortal (`assets/js/hooks/chat_portal.js`)

Moves the LiveComponent's DOM into the sidebar shell container. This is needed because the LiveComponent is rendered inside a specific LiveView, but the sidebar shell is in the layout.

- `mounted()`: Finds `#chat-sidebar-slot` and appends this element
- `updated()`: Re-checks placement, re-appends if moved

---

## Function Components

### Module: `SocialScribeWeb.ChatComponents`

**File:** `lib/social_scribe_web/components/chat_components.ex`

Stateless function components for all chat UI elements:

| Component | Description |
|-----------|-------------|
| `chat_floating_button/1` | Fixed bottom-right indigo circle with sparkles icon. Fires `toggle_chat_sidebar` |
| `chat_sidebar_shell/1` | Fixed right panel (400px), slide-in/out animation via `translate-x-0`/`translate-x-full` |
| `chat_message_bubble/1` | Message rendering - right-aligned for user, left-aligned for assistant, centered for system |
| `mention_pill/1` | Inline avatar + CRM badge pill for contacts |
| `mention_dropdown/1` | Contact search results popup above input |
| `context_type_picker/1` | "Add context" dropdown with "Meetings" option |
| `meeting_dropdown/1` | Meeting search with search input, results, and "Load more" button (300ms debounce) |
| `meeting_pill/1` | Video camera icon + truncated title + remove button |
| `crm_icon/1` | HubSpot (orange sprocket) or Salesforce (blue cloud) inline SVG |
| `source_badges/1` | Shows CRM/meeting provider icons below AI responses |
| `source_icons/1` | Shows CRM/meeting provider icons below input area |

### Message Rendering

`chat_message_bubble` handles three message types differently:

**User messages:** Parsed via `parse_content_with_mentions/2` - splits content by `@word` patterns using regex, replaces matches with contact maps that render as styled pills. Background: `bg-[#f0f5f5]`.

**Assistant messages:** Parsed via `parse_markdown/2` using Earmark to convert markdown to HTML. If the message has mentioned contacts, `process_mentions_in_html/2` replaces `@firstname` occurrences with styled inline HTML pills. Rendered as `raw()` HTML with Tailwind prose classes.

**System messages:** Centered, gray, italic text.

---

## Layout Integration

### Dashboard Layout (`lib/social_scribe_web/components/layouts/dashboard.html.heex`)

The chat sidebar is rendered at the layout level, outside of any specific LiveView:

```heex
<!-- Sidebar Shell (fixed right panel, always in DOM) -->
<.chat_sidebar_shell chat_open={assigns[:chat_open] || false}>
  <.live_component
    module={ChatSidebarComponent}
    id="chat-sidebar"
    current_user={@current_user}
  />
</.chat_sidebar_shell>

<!-- Floating Button (hidden when sidebar is open) -->
<.chat_floating_button :if={!(assigns[:chat_open] || false)} />
```

### LiveHooks (`lib/social_scribe_web/live_hooks.ex`)

```elixir
def on_mount(:attach_chat_sidebar, _params, _session, socket) do
  {:cont, assign(socket, :chat_open, false)}
end
```

Registered in the router's authenticated live session:

```elixir
live_session :require_authenticated_user,
  on_mount: [
    {SocialScribeWeb.UserAuth, :ensure_authenticated},
    {SocialScribeWeb.LiveHooks, :assign_current_path},
    {SocialScribeWeb.LiveHooks, :attach_chat_sidebar}
  ]
```

This ensures every authenticated LiveView starts with `chat_open: false`.

---

## End-to-End Data Flows

### 1. Opening the Chat Sidebar

```
User clicks floating sparkles button
  -> handle_event("toggle_chat_sidebar") in parent LiveView
  -> socket.assigns.chat_open = true
  -> Layout re-renders:
     - chat_sidebar_shell gets translate-x-0 (slides in)
     - Floating button hidden via :if condition
  -> ChatSidebarComponent mounts (if first time):
     - Chat.get_or_create_active_conversation(user.id)
     - Loads existing messages
```

### 2. @Mention Contact Search

```
User types "@Jo" in contenteditable
  -> MentionInput hook detects /@(\S+)$/ match with "Jo"
  -> pushEventTo("mention_search", {query: "Jo"})
  -> ChatSidebarComponent sets searching_contacts: true
  -> send(self(), {:chat_contact_search, "Jo", user_id})
  -> Parent LiveView (ChatHandlers) receives message
  -> ContactSearch.search(user_id, "Jo")
     -> Task.async: HubspotApi.search_contacts(credential, "Jo")
     -> Task.async: SalesforceApi.search_contacts(credential, "Jo")
     -> Task.await_many(10_000)
     -> Flatten, limit 10
  -> send_update(ChatSidebarComponent, mention_results: results)
  -> Dropdown renders above input with contact results + CRM icons
```

### 3. Selecting a Contact

```
User clicks "John Doe" (HubSpot) in dropdown
  -> handle_event("select_mention", %{id: "123", provider: "hubspot", ...})
  -> Appends to mentioned_contacts list
  -> Clears mention_query and mention_results
  -> push_event("insert_mention_pill", %{firstname: "John", provider: "hubspot"})
  -> MentionInput hook receives event:
     - Finds @Jo text in DOM using TreeWalker
     - Replaces with <span> pill element (avatar + CRM badge)
     - Positions cursor after pill
```

### 4. Adding Meeting Context

```
User clicks "Add context" button
  -> toggle_context_menu: context_menu_open = true
  -> context_type_picker dropdown appears

User clicks "Meetings"
  -> select_context_type("meetings")
  -> context_type = :meetings, searching_meetings = true
  -> send(self(), {:chat_meeting_list, user_id, 0})
  -> Parent fetches MeetingSearch.list_recent(user_id)
  -> send_update with meeting_search_results
  -> meeting_dropdown renders with results + search input

User searches "Q4" in meeting dropdown
  -> meeting_search event with query "Q4"
  -> send(self(), {:chat_meeting_search, "Q4", user_id, 0})
  -> Results returned to component

User clicks a meeting
  -> select_meeting(%{id: 42, title: "Q4 Planning"})
  -> Added to mentioned_meetings (duplicate check)
  -> Dropdown closes, meeting_pill appears below input
```

### 5. Sending a Message

```
User types message and presses Enter
  -> MentionInput hook: submitMessage()
     - getPlainText() converts pills to @firstname text
     - Sets hidden input value
     - Dispatches form submit

  -> ChatSidebarComponent handle_event("send_message")
     - Parses mentioned_contacts JSON from hidden field
     - Parses mentioned_meetings JSON from hidden field
     - Chat.add_message(conversation.id, %{role: "user", ...})
     - Chat.maybe_set_title(conversation, message)
     - Appends user message to UI immediately
     - Sets sending: true (shows "Thinking..." dots)
     - Clears mentioned_contacts and mentioned_meetings
     - push_event("clear_chat_input") to JS hook
     - send(self(), {:chat_ask_ai, message, contacts, conversation_id, meetings})

  -> Parent LiveView (ChatHandlers):
     - Loads full conversation with history
     - Fallback: if no mentions in current message, uses last mentioned from history
     - ChatAi.ask(message, contacts, history, meetings)
       - Parallel: fetch full CRM contact data for each mentioned contact
       - Parallel: fetch meeting data + transcripts
       - Build prompt with all context
       - GeminiClient.generate(prompt) -> AI response
     - Chat.add_message(conversation_id, %{role: "assistant", content: response, sources: sources})
     - send_update(ChatSidebarComponent, messages: updated_messages, sending: false)

  -> ChatSidebarComponent updates:
     - Messages list refreshed with AI response
     - sending = false, "Thinking..." animation removed
     - ChatScroll hook auto-scrolls to bottom
     - Source badges displayed below AI response
```

### 6. Conversation History

```
User clicks "History" tab
  -> switch_tab("history")
  -> Chat.list_conversations(user_id) - ordered by updated_at desc
  -> Renders conversation list with titles and dates

User clicks a conversation
  -> select_conversation(id)
  -> Chat.get_conversation!(id) with messages
  -> Switches to chat tab with loaded messages

User clicks trash icon
  -> delete_conversation(id) with confirmation dialog
  -> Chat.delete_conversation(id)
  -> If deleted conversation was active: falls back to next, or creates new
  -> Refreshes conversation list
```

---

## Error Handling and Resilience

### CRM Search Failures

`ContactSearch.search/2` wraps each CRM call in its own `Task.async`. If one CRM fails:
- Its results return as `[]`
- The other CRM's results are still displayed
- No error is surfaced to the user

### AI Generation Failures

If `ChatAi.ask/4` returns `{:error, _}`:
- A generic error message is persisted as an assistant message: "I'm sorry, I encountered an error processing your request. Please try again."
- `sending: false` is set on the component
- The conversation continues normally for future messages

### Contact Fetch Failures

If fetching a specific contact's full data fails during AI context building:
- The failed contact is filtered out
- Available contacts are still included in the prompt
- The AI response may be less informed but doesn't fail entirely

### Meeting Fetch Failures

If `Meetings.get_meeting_with_details/1` returns `nil`:
- The meeting is skipped
- Other meetings are still included
- Falls back to basic format if `generate_prompt_for_meeting/1` fails

### Fallback Mention Logic

When a user sends a follow-up message without explicitly mentioning contacts or meetings:
- The handler scans conversation history in reverse
- Finds the most recent user message that had `mentioned_contacts` or `mentioned_meetings`
- Uses those mentions as context for the current AI call
- Enables natural multi-turn conversations like:
  1. "Tell me about @John from HubSpot" (mentions John)
  2. "What's his email?" (no mention - falls back to John from message 1)

---

## Key Design Decisions

### LiveComponent + Parent Communication via Messages

The chat sidebar is a LiveComponent, not a separate LiveView. This means it can't directly call async operations. Instead:
- Component sends messages to parent via `send(self(), {:chat_...})`
- Parent processes the message, calls services, and returns results via `send_update(Component, ...)`

This pattern was chosen because LiveComponents share the parent's process and can't independently handle async work.

### `@before_compile` Macro for Handler Injection

The `ChatHandlers` module uses `@before_compile` rather than regular `defoverridable` or behaviour callbacks. This ensures chat handlers are compiled **after** the module's own handlers, so they act as fallback clauses that don't interfere with page-specific event handling.

### Contenteditable + Hidden Input Pattern

A `contenteditable` div is used instead of a standard `<input>` or `<textarea>` because:
- Standard inputs can't render inline rich elements (pills with avatars and icons)
- The contenteditable div allows mixing text nodes with non-editable `<span>` elements
- A hidden `<input>` is synced with the plain text representation for form submission
- `phx-update="ignore"` prevents LiveView from overwriting the JS-managed DOM

### JSONB for Flexible Context Storage

`mentioned_contacts`, `mentioned_meetings`, and `sources` use PostgreSQL JSONB columns rather than separate tables because:
- The data is denormalized snapshots (contact info at time of message, not live references)
- Schema flexibility - different providers have different contact shapes
- Simpler queries - no joins needed to render message history
- The data is always read together with the message

### ChatPortal JS Hook for Layout Placement

The LiveComponent is rendered inside a specific LiveView, but the sidebar needs to be in a fixed position outside of the main content flow. The `ChatPortal` hook solves this by physically moving the component's DOM into the sidebar shell container in the layout, while keeping the LiveView ownership intact.

### Conversation Auto-Titling

Conversations start without a title. When the first user message is sent, `maybe_set_title/2` takes the first 50 characters as the title (with "..." suffix if truncated). This avoids requiring users to name conversations and provides a useful preview in the history tab.

---

## Extending the Feature

### Adding a New Context Type (e.g., Documents, Emails)

1. Add a new option to `context_type_picker` in `chat_components.ex`
2. Create a search module (e.g., `Chat.DocumentSearch`) following the `MeetingSearch` pattern
3. Add state assigns in `ChatSidebarComponent.mount/1` for the new context type
4. Add `handle_event` clauses for `select_context_type` with the new type
5. Add a handler in `ChatHandlers` for the search message
6. Create a pill component and dropdown component for the new context type
7. Update `ChatAi.ask/4` to accept and process the new context
8. Add a `mentioned_{type}` JSONB column to `chat_messages` via migration

### Adding Streaming Responses

Currently, AI responses are returned as a single block after the full Gemini response is received. To add streaming:

1. Switch `GeminiClient.generate/1` to use Gemini's streaming endpoint (`streamGenerateContent`)
2. In `ChatHandlers`, stream chunks to the component via repeated `send_update` calls
3. Update `ChatSidebarComponent` to append to the current assistant message as chunks arrive
4. Mark the message as complete when the stream ends, then persist the full response

### Adding a New CRM Provider

Contact search is already multi-provider. To add a new CRM (e.g., Zoho):

1. Create the CRM's API client and behaviour modules
2. Add a `get_user_zoho_credential/1` function to `Accounts`
3. Add a `maybe_add_task(tasks, :zoho, credential, query)` clause in `ContactSearch`
4. Add a `:zoho` case in `ChatAi.fetch_single_contact/1`
5. Add a `crm_icon` SVG for the new provider in `ChatComponents`
6. Add the SVG to `getCrmIconSvg()` in `mention_input.js`

### Testing with Mocks

The feature uses behaviour modules for CRM APIs (`HubspotApiBehaviour`, `SalesforceApiBehaviour`), enabling test mocks via Mox. Test files:

- `test/social_scribe/chat/chat_test.exs` - Context CRUD tests
- `test/social_scribe/chat/chat_ai_test.exs` - AI integration with mocked APIs
- `test/support/fixtures/chat_fixtures.ex` - Test data builders
- `test/social_scribe_web/live/chat/chat_sidebar_component_test.exs` - Component tests
- `test/social_scribe_web/live/chat/chat_sidebar_mox_test.exs` - Component with mocked CRMs