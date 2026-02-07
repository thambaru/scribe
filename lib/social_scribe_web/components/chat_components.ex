defmodule SocialScribeWeb.ChatComponents do
  @moduledoc """
  Stateless function components for the Ask Anything chat sidebar.
  """
  use Phoenix.Component

  import SocialScribeWeb.CoreComponents, only: [icon: 1]
  import Phoenix.HTML, only: [raw: 1]

  @doc """
  Renders the floating chat button (bottom-right sparkles icon).
  """
  attr :click, :string, default: "toggle_chat_sidebar"

  def chat_floating_button(assigns) do
    ~H"""
    <button
      phx-click={@click}
      class="fixed bottom-6 right-6 z-40 w-14 h-14 rounded-full bg-indigo-600 text-white shadow-lg hover:bg-indigo-700 transition-colors flex items-center justify-center focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
      aria-label="Open Ask Anything chat"
      id="chat-floating-button"
    >
      <.icon name="hero-sparkles" class="size-6" />
    </button>
    """
  end

  @doc """
  Renders a chat message bubble. User messages are right-aligned indigo,
  AI messages are left-aligned gray, system messages are centered.
  """
  attr :role, :string, required: true
  attr :content, :string, required: true
  attr :mentioned_contacts, :list, default: []
  attr :sources, :list, default: []

  def chat_message_bubble(assigns) do
    assigns =
      assigns
      |> assign(:parsed_content, parse_message_content(assigns.content, assigns.mentioned_contacts, assigns.role))
      |> assign(:is_markdown, assigns.role == "assistant")

    ~H"""
    <div class={[
      "flex w-full mb-3",
      @role == "user" && "justify-end",
      @role == "assistant" && "justify-start",
      @role == "system" && "justify-center"
    ]}>
      <div class={[
        "max-w-[85%] rounded-2xl px-4 py-2.5 text-sm",
        @role == "user" && "bg-[#f0f5f5] text-gray-800 rounded-br-md",
        @role == "assistant" && "bg-transparent text-gray-800 rounded-bl-md",
        @role == "system" && "bg-gray-50 text-gray-500 text-xs italic"
      ]}>
        <div class={[
          "break-words",
          @is_markdown && "prose prose-sm max-w-none prose-p:my-1 prose-ul:my-1 prose-li:my-0"
        ]}>
          <%= if @is_markdown do %>
            <%= raw(@parsed_content) %>
          <% else %>
            <span :for={part <- @parsed_content}><span
                :if={is_map(part)}
                class={[
                  "inline-flex items-center gap-1 px-1 pr-2 py-0.5 mx-0.5 rounded-full text-xs font-medium align-middle",
                  @role == "user" && "bg-white",
                  @role != "user" && "bg-indigo-100 text-indigo-700"
                ]}
              ><span class="relative inline-flex flex-shrink-0">
                  <span class="w-5 h-5 rounded-full bg-indigo-100 text-indigo-700 flex items-center justify-center text-[10px] font-semibold leading-none">
                    {String.first(part.firstname || "?")}
                  </span>
                  <span class="absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full bg-white flex items-center justify-center">
                    <.crm_icon provider={part.provider} class="size-2.5" />
                  </span>
                </span>{part.firstname}</span><%= if !is_map(part), do: part %></span>
          <% end %>
        </div>
        <.source_badges :if={@role == "assistant" && @sources != []} sources={@sources} />
      </div>
    </div>
    """
  end

  @doc """
  Renders an inline mention pill with CRM icon and contact first name.
  """
  attr :contact, :map, required: true

  def mention_pill(assigns) do
    firstname = Map.get(assigns.contact, :firstname, Map.get(assigns.contact, "firstname", "Contact"))
    assigns = assign(assigns, :firstname, firstname)

    ~H"""
    <span class="inline-flex items-center gap-1 px-1 pr-2 py-0.5 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium">
      <span class="relative inline-flex flex-shrink-0">
        <span class="w-5 h-5 rounded-full bg-indigo-200 text-indigo-700 flex items-center justify-center text-[10px] font-semibold leading-none">
          {String.first(@firstname || "?")}
        </span>
        <span class="absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full bg-white flex items-center justify-center">
          <.crm_icon provider={provider_atom(@contact)} class="size-2.5" />
        </span>
      </span>
      <span>{@firstname}</span>
    </span>
    """
  end

  @doc """
  Renders the contact search results dropdown above the input.
  """
  attr :results, :list, required: true
  attr :searching, :boolean, default: false
  attr :target, :any, default: nil

  def mention_dropdown(assigns) do
    ~H"""
    <div class="absolute bottom-full left-0 right-0 mb-1 bg-white rounded-lg shadow-lg border border-gray-200 max-h-60 overflow-y-auto z-50">
      <div :if={@searching} class="p-3 text-sm text-gray-500 text-center">
        <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-indigo-600 mx-auto mb-1">
        </div>
        Searching contacts...
      </div>
      <div :if={!@searching && @results == []} class="p-3 text-sm text-gray-500 text-center">
        No contacts found
      </div>
      <button
        :for={contact <- @results}
        type="button"
        phx-click="select_mention"
        phx-value-id={contact.id}
        phx-value-provider={contact.provider}
        phx-value-firstname={contact.firstname}
        phx-value-lastname={contact.lastname}
        phx-value-email={contact.email}
        phx-value-credential_id={contact.credential_id}
        phx-target={@target}
        class="w-full text-left px-3 py-2 hover:bg-gray-50 flex items-center gap-2 border-b border-gray-100 last:border-0"
      >
        <div class="w-7 h-7 rounded-full bg-gray-200 flex items-center justify-center text-xs font-medium text-gray-600 flex-shrink-0">
          {String.first(contact.firstname || "?")}
        </div>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-medium text-gray-900 truncate">
            {contact.firstname} {contact.lastname}
          </div>
          <div class="text-xs text-gray-500 truncate">{contact.email}</div>
        </div>
        <.crm_icon provider={contact.provider} class="size-4 flex-shrink-0" />
      </button>
    </div>
    """
  end

  @doc """
  Renders the context type picker dropdown (Contacts / Meetings).
  """
  attr :target, :any, default: nil

  def context_type_picker(assigns) do
    ~H"""
    <div class="absolute bottom-full left-0 mb-1 bg-white rounded-lg shadow-lg border border-gray-200 z-50 w-48">
      <button
        type="button"
        phx-click="select_context_type"
        phx-value-type="meetings"
        phx-target={@target}
        class="w-full text-left px-3 py-2.5 hover:bg-gray-50 flex items-center gap-2 rounded-lg"
      >
        <.icon name="hero-video-camera" class="size-4 text-gray-500" />
        <span class="text-sm text-gray-700">Meetings</span>
      </button>
    </div>
    """
  end

  @doc """
  Renders the meeting search dropdown with search input, results, and load more.
  """
  attr :results, :list, required: true
  attr :searching, :boolean, default: false
  attr :has_more, :boolean, default: false
  attr :query, :string, default: ""
  attr :target, :any, default: nil

  def meeting_dropdown(assigns) do
    ~H"""
    <div class="absolute bottom-full left-0 right-0 mb-1 bg-white rounded-lg shadow-lg border border-gray-200 max-h-72 flex flex-col z-50">
      <div class="p-2 border-b border-gray-100">
        <input
          type="text"
          placeholder="Search meetings..."
          value={@query}
          phx-keyup="meeting_search"
          phx-target={@target}
          phx-debounce="300"
          class="w-full text-sm border border-gray-200 rounded-md px-2.5 py-1.5 focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500"
          autofocus
        />
      </div>
      <div class="overflow-y-auto flex-1">
        <div :if={@searching} class="p-3 text-sm text-gray-500 text-center">
          <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-indigo-600 mx-auto mb-1">
          </div>
          Searching meetings...
        </div>
        <div
          :if={!@searching && @results == []}
          class="p-3 text-sm text-gray-500 text-center"
        >
          No meetings found
        </div>
        <button
          :for={meeting <- @results}
          type="button"
          phx-click="select_meeting"
          phx-value-id={meeting.id}
          phx-value-title={meeting.title}
          phx-target={@target}
          class="w-full text-left px-3 py-2 hover:bg-gray-50 flex items-center gap-2 border-b border-gray-100 last:border-0"
        >
          <div class="w-7 h-7 rounded-full bg-indigo-50 flex items-center justify-center flex-shrink-0">
            <.icon name="hero-video-camera" class="size-3.5 text-indigo-500" />
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-medium text-gray-900 truncate">
              {meeting.title}
            </div>
            <div class="text-xs text-gray-500">
              {format_meeting_date(meeting.recorded_at)} · {format_meeting_duration(meeting.duration_seconds)} · {meeting.participant_count} attendees
            </div>
          </div>
        </button>
        <button
          :if={@has_more && !@searching}
          type="button"
          phx-click="load_more_meetings"
          phx-target={@target}
          class="w-full text-center px-3 py-2 text-xs text-indigo-600 hover:bg-indigo-50 font-medium"
        >
          Load more...
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a meeting context pill with calendar icon and meeting title.
  """
  attr :meeting, :map, required: true
  attr :target, :any, default: nil

  def meeting_pill(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 pl-2 pr-1 py-0.5 rounded-full bg-indigo-50 text-indigo-700 text-xs font-medium">
      <.icon name="hero-video-camera" class="size-3" />
      <span class="truncate max-w-[120px]">{Map.get(@meeting, :title, Map.get(@meeting, "title", "Meeting"))}</span>
      <button
        type="button"
        phx-click="remove_meeting"
        phx-value-id={Map.get(@meeting, :id, Map.get(@meeting, "id"))}
        phx-target={@target}
        class="ml-0.5 p-0.5 rounded-full hover:bg-indigo-100"
      >
        <.icon name="hero-x-mark" class="size-3" />
      </button>
    </span>
    """
  end

  @doc """
  Renders a small CRM provider icon (HubSpot sprocket or Salesforce cloud).
  """
  attr :provider, :any, required: true
  attr :class, :string, default: "size-4"
  attr :style, :string, default: ""

  def crm_icon(assigns) do
    ~H"""
    <span :if={normalize_provider(@provider) == :hubspot} title="HubSpot" class={["inline-block", "bg-gray-200 rounded-[10px]", @class]} style={@style}>
      <svg viewBox="0 0 24 24" fill="currentColor" class={"text-orange-500 " <> @class}>
        <path d="M17.58 10.1V7.64a2.08 2.08 0 0 0 1.21-1.88v-.06A2.08 2.08 0 0 0 16.71 3.62h-.06A2.08 2.08 0 0 0 14.57 5.7v.06a2.08 2.08 0 0 0 1.21 1.88V10.1a5.33 5.33 0 0 0-2.4 1.18l-6.39-4.97a2.2 2.2 0 0 0 .06-.51 2.24 2.24 0 1 0-2.24 2.24c.35 0 .68-.09.98-.24l6.27 4.88a5.37 5.37 0 0 0 .14 6.06l-1.93 1.93a1.63 1.63 0 0 0-.47-.08 1.66 1.66 0 1 0 1.66 1.66 1.63 1.63 0 0 0-.08-.47l1.9-1.9a5.38 5.38 0 1 0 4.14-9.88zm-.93 7.64a2.54 2.54 0 1 1 0-5.08 2.54 2.54 0 0 1 0 5.08z" />
      </svg>
    </span>
    <span :if={normalize_provider(@provider) == :salesforce} title="Salesforce" class={["inline-block", "bg-gray-200 rounded-[10px]", @class]} style={@style}>
      <svg viewBox="0 0 24 24" fill="currentColor" class={"text-[#00A1E0] " <> @class}>
        <path d="M10.05 5.43a4.35 4.35 0 0 1 3.37-1.6 4.39 4.39 0 0 1 4.1 2.87 3.65 3.65 0 0 1 1.47-.31 3.69 3.69 0 0 1 3.69 3.69 3.69 3.69 0 0 1-3.69 3.69h-.15l-.01.14a3.9 3.9 0 0 1-3.87 3.46 3.88 3.88 0 0 1-2.38-.82 4.67 4.67 0 0 1-3.54 1.63 4.68 4.68 0 0 1-4.44-3.19A3.43 3.43 0 0 1 3 11.73a3.43 3.43 0 0 1 2.79-3.37 4.07 4.07 0 0 1-.06-.72A4.14 4.14 0 0 1 9.87 3.5c.07 0 .13.01.18.01v-.01l.01.01-.01 1.92z" />
      </svg>
    </span>
    """
  end

  @doc """
  Renders source badges below AI responses showing which CRMs provided data.
  """
  attr :sources, :list, required: true

  def source_badges(assigns) do
    providers =
      assigns.sources
      |> Enum.map(fn source -> Map.get(source, :provider, Map.get(source, "provider")) end)
      |> Enum.uniq()

    crm_providers = Enum.filter(providers, &(normalize_provider(&1) != :meeting))
    has_meetings = Enum.any?(providers, &(normalize_provider(&1) == :meeting))
    total = length(crm_providers) + if(has_meetings, do: 1, else: 0)
    indexed_providers = Enum.with_index(crm_providers)

    assigns =
      assigns
      |> assign(:indexed_providers, indexed_providers)
      |> assign(:has_meetings, has_meetings)
      |> assign(:total, total)

    ~H"""
    <div class="flex items-center gap-1.5 mt-2 pt-1.5">
      <span class="text-xs text-gray-400">Sources</span>
      <span class="flex items-center -space-x-1.5">
        <.crm_icon
          :for={{provider, idx} <- @indexed_providers}
          provider={provider}
          class="size-5 ring-2 ring-white rounded-full"
          style={"position:relative;z-index:#{@total - idx}"}
        />
        <span
          :if={@has_meetings}
          title="Meeting"
          class="size-5 ring-2 ring-white rounded-full bg-gray-200 flex items-center justify-center"
          style="position:relative;z-index:0"
        >
          <.icon name="hero-video-camera" class="size-3 text-indigo-500" />
        </span>
      </span>
    </div>
    """
  end

  @doc """
  Renders stacked CRM icons below the input showing which CRMs are referenced by mentioned contacts.
  """
  attr :contacts, :list, required: true
  attr :meetings, :list, default: []

  def source_icons(assigns) do
    providers =
      assigns.contacts
      |> Enum.map(fn c -> Map.get(c, :provider, Map.get(c, "provider")) end)
      |> Enum.uniq()

    has_meetings = assigns.meetings != []
    total = length(providers) + if(has_meetings, do: 1, else: 0)
    indexed_providers = Enum.with_index(providers)

    assigns =
      assigns
      |> assign(:indexed_providers, indexed_providers)
      |> assign(:has_meetings, has_meetings)
      |> assign(:total, total)

    ~H"""
    <div :if={@indexed_providers != [] || @has_meetings} class="flex items-center -space-x-1.5">
      <.crm_icon
        :for={{provider, idx} <- @indexed_providers}
        provider={provider}
        class="size-5 ring-2 ring-white rounded-full"
        style={"position:relative;z-index:#{@total - idx}"}
      />
      <span :if={@has_meetings} title="Meetings" class="size-5 ring-2 ring-white rounded-full bg-gray-200 flex items-center justify-center" style="position:relative;z-index:0">
        <.icon name="hero-video-camera" class="size-3 text-indigo-500" />
      </span>
    </div>
    """
  end

  @doc """
  The outer sidebar shell container rendered in the layout.
  """
  attr :chat_open, :boolean, default: false

  slot :inner_block

  def chat_sidebar_shell(assigns) do
    ~H"""
    <div
      id="chat-sidebar-panel"
      phx-hook="ChatSidebar"
      class={[
        "fixed top-0 right-0 h-full w-[400px] bg-white shadow-2xl z-50 transform flex flex-col",
        @chat_open && "translate-x-0",
        !@chat_open && "translate-x-full"
      ]}
    >
      <div id="chat-sidebar-slot" class="flex flex-col flex-1 min-h-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Helpers
  @doc false
  defp parse_message_content(content, mentioned_contacts, role) when is_binary(content) do
    case role do
      "assistant" ->
        # Parse markdown for assistant messages
        parse_markdown(content, mentioned_contacts)

      _ ->
        # Parse mentions for user/system messages
        parse_content_with_mentions(content, mentioned_contacts)
    end
  end

  defp parse_message_content(content, _, _), do: [to_string(content)]

  @doc false
  defp parse_markdown(content, mentioned_contacts) do
    # Convert markdown to HTML using Earmark
    case Earmark.as_html(content) do
      {:ok, html, _} ->
        # Process mentions in the HTML if needed
        if mentioned_contacts != [] do
          process_mentions_in_html(html, mentioned_contacts)
        else
          html
        end

      {:error, _, _} ->
        # Fall back to plain text if markdown parsing fails
        content
    end
  end

  defp process_mentions_in_html(html, mentioned_contacts) do
    # Build a map of @firstname to contact for quick lookup
    mention_map =
      mentioned_contacts
      |> Enum.map(fn contact ->
        firstname = Map.get(contact, :firstname, Map.get(contact, "firstname"))
        {"@#{firstname}", contact}
      end)
      |> Map.new()

    # Replace @mentions with styled spans showing avatar + CRM badge
    Enum.reduce(mention_map, html, fn {mention, contact}, acc ->
      firstname = Map.get(contact, :firstname, Map.get(contact, "firstname"))
      initial = if firstname, do: String.first(firstname), else: "?"
      provider = Map.get(contact, :provider, Map.get(contact, "provider", "unknown"))
      provider_str = to_string(provider)

      crm_svg = crm_icon_svg(provider_str)

      replacement = ~s(<span class="inline-flex items-center gap-1 px-1 pr-2 py-0.5 mx-0.5 rounded-full text-xs font-medium bg-indigo-100 text-indigo-700 align-middle"><span style="position:relative;display:inline-flex;flex-shrink:0;"><span style="width:20px;height:20px;border-radius:9999px;background:#c7d2fe;color:#4338ca;display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:600;line-height:1;">#{initial}</span><span style="position:absolute;bottom:-2px;right:-2px;width:12px;height:12px;border-radius:9999px;background:white;display:flex;align-items:center;justify-content:center;">#{crm_svg}</span></span>#{firstname}</span>)

      String.replace(acc, mention, replacement)
    end)
  end

  defp crm_icon_svg("hubspot") do
    ~s(<svg viewBox="0 0 24 24" fill="currentColor" style="width:10px;height:10px;color:#f97316;"><path d="M17.58 10.1V7.64a2.08 2.08 0 0 0 1.21-1.88v-.06A2.08 2.08 0 0 0 16.71 3.62h-.06A2.08 2.08 0 0 0 14.57 5.7v.06a2.08 2.08 0 0 0 1.21 1.88V10.1a5.33 5.33 0 0 0-2.4 1.18l-6.39-4.97a2.2 2.2 0 0 0 .06-.51 2.24 2.24 0 1 0-2.24 2.24c.35 0 .68-.09.98-.24l6.27 4.88a5.37 5.37 0 0 0 .14 6.06l-1.93 1.93a1.63 1.63 0 0 0-.47-.08 1.66 1.66 0 1 0 1.66 1.66 1.63 1.63 0 0 0-.08-.47l1.9-1.9a5.38 5.38 0 1 0 4.14-9.88zm-.93 7.64a2.54 2.54 0 1 1 0-5.08 2.54 2.54 0 0 1 0 5.08z"/></svg>)
  end

  defp crm_icon_svg("salesforce") do
    ~s(<svg viewBox="0 0 24 24" fill="currentColor" style="width:10px;height:10px;color:#00A1E0;"><path d="M10.05 5.43a4.35 4.35 0 0 1 3.37-1.6 4.39 4.39 0 0 1 4.1 2.87 3.65 3.65 0 0 1 1.47-.31 3.69 3.69 0 0 1 3.69 3.69 3.69 3.69 0 0 1-3.69 3.69h-.15l-.01.14a3.9 3.9 0 0 1-3.87 3.46 3.88 3.88 0 0 1-2.38-.82 4.67 4.67 0 0 1-3.54 1.63 4.68 4.68 0 0 1-4.44-3.19A3.43 3.43 0 0 1 3 11.73a3.43 3.43 0 0 1 2.79-3.37 4.07 4.07 0 0 1-.06-.72A4.14 4.14 0 0 1 9.87 3.5c.07 0 .13.01.18.01v-.01l.01.01-.01 1.92z"/></svg>)
  end

  defp crm_icon_svg(_), do: ""

  defp provider_atom(%{provider: p}) when is_atom(p), do: p
  defp provider_atom(%{provider: p}) when is_binary(p), do: String.to_existing_atom(p)
  defp provider_atom(%{"provider" => p}) when is_atom(p), do: p
  defp provider_atom(%{"provider" => p}) when is_binary(p), do: String.to_existing_atom(p)
  defp provider_atom(_), do: :unknown

  defp normalize_provider(p) when is_atom(p), do: p
  defp normalize_provider("meeting"), do: :meeting
  defp normalize_provider(p) when is_binary(p), do: String.to_existing_atom(p)
  defp normalize_provider(_), do: :unknown

  defp format_meeting_date(nil), do: ""

  defp format_meeting_date(datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y")
  end

  defp format_meeting_duration(nil), do: ""

  defp format_meeting_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)

    cond do
      minutes < 1 -> "< 1 min"
      minutes == 1 -> "1 min"
      minutes < 60 -> "#{minutes} min"
      true ->
        hours = div(minutes, 60)
        rem_min = rem(minutes, 60)
        if rem_min == 0, do: "#{hours}h", else: "#{hours}h #{rem_min}m"
    end
  end

  defp format_meeting_duration(_), do: ""

  @doc false
  defp parse_content_with_mentions(content, mentioned_contacts) when is_binary(content) do
    # Build a map of @firstname to contact for quick lookup
    mention_map =
      mentioned_contacts
      |> Enum.map(fn contact ->
        firstname = Map.get(contact, :firstname, Map.get(contact, "firstname"))
        {"@#{firstname}", contact}
      end)
      |> Map.new()

    # Split content by @mentions - captures @word patterns
    parts = Regex.split(~r/(@\w+)/, content, include_captures: true, trim: false)

    Enum.map(parts, fn part ->
      case Map.get(mention_map, part) do
        nil ->
          part
        contact ->
          provider = Map.get(contact, :provider, Map.get(contact, "provider"))
          %{
            firstname: Map.get(contact, :firstname, Map.get(contact, "firstname")),
            provider: if(provider, do: normalize_provider(provider), else: :unknown)
          }
      end
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_content_with_mentions(content, _), do: [to_string(content)]
end
