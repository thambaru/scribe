defmodule SocialScribeWeb.MeetingLive.SalesforceModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  use SocialScribeWeb.MeetingLive.IntegrationModalComponent,
    search_message: :salesforce_search,
    generate_message: :generate_salesforce_suggestions,
    apply_message: :apply_salesforce_updates

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "salesforce-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">Update in Salesforce</h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Here are suggested updates to sync with your integrations based on this
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
          selected_contact={@selected_contact}
          contacts={@contacts}
          loading={@searching}
          open={@dropdown_open}
          query={@query}
          target={@myself}
          error={@error}
        />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true

  defp suggestions_section(assigns) do
    assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))

    ~H"""
    <div class="space-y-4">
      <%= if @loading and Enum.empty?(@suggestions) do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.salesforce_suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} target={@myself} />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update Salesforce"
              submit_class="bg-[#00A1E0] hover:bg-[#0082B4]"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} fields in 1 integration selected to update"}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :suggestion, :map, required: true
  attr :class, :string, default: nil
  attr :target, :any, default: nil

  defp salesforce_suggestion_card(assigns) do
    ~H"""
    <div class={["bg-slate-50 rounded-2xl p-6 mb-4", @class]}>
      <div class="flex items-start justify-between">
        <div class="flex items-start gap-3">
          <div class="flex items-center h-5 pt-0.5">
            <input
              type="checkbox"
              checked={@suggestion.apply}
              phx-click={JS.dispatch("click", to: "#salesforce-suggestion-apply-#{@suggestion.field}")}
              class="h-4 w-4 rounded-[3px] border-slate-300 text-[#00A1E0] accent-[#00A1E0] focus:ring-0 focus:ring-offset-0 cursor-pointer"
            />
          </div>
          <div class="text-sm font-semibold text-slate-900 leading-5">{@suggestion.label}</div>
        </div>

        <div class="flex items-center gap-3 pt-0.5">
          <span
            class={[
              "inline-flex items-center rounded-full bg-blue-100 px-2 py-1 text-xs font-medium text-blue-800",
              if(@suggestion.apply, do: "opacity-100", else: "opacity-0 pointer-events-none")
            ]}
            aria-hidden={to_string(!@suggestion.apply)}
          >
            1 update selected
          </span>
          <button
            type="button"
            phx-click="toggle_details"
            phx-value-field={@suggestion.field}
            phx-target={@target}
            class="text-xs text-slate-500 hover:text-slate-700 font-medium"
          >
            {if Map.get(@suggestion, :hidden, false), do: "Show details", else: "Hide details"}
          </button>
        </div>
      </div>

      <div :if={!Map.get(@suggestion, :hidden, false)} class="mt-2 pl-8">
        <div class="text-sm font-medium text-slate-700 leading-5 ml-1">{@suggestion.label}</div>

        <div class="relative mt-2">
          <input
            id={"salesforce-suggestion-apply-#{@suggestion.field}"}
            type="checkbox"
            name={"apply[#{@suggestion.field}]"}
            value="1"
            checked={@suggestion.apply}
            class="absolute -left-8 top-1/2 -translate-y-1/2 h-4 w-4 rounded-[3px] border-slate-300 text-[#00A1E0] accent-[#00A1E0] focus:ring-0 focus:ring-offset-0 cursor-pointer"
          />

          <div class="grid grid-cols-[1fr_32px_1fr] items-center gap-6">
            <input
              type="text"
              readonly
              value={@suggestion.current_value || ""}
              placeholder="No existing value"
              class={[
                "block w-full shadow-sm text-sm bg-white border border-gray-300 rounded-[7px] py-1.5 px-2",
                if(@suggestion.current_value && @suggestion.current_value != "", do: "line-through text-gray-500", else: "text-gray-400")
              ]}
            />

            <div class="w-8 flex justify-center text-slate-400">
              <.icon name="hero-arrow-long-right" class="h-7 w-7" />
            </div>

            <input
              type="text"
              name={"values[#{@suggestion.field}]"}
              value={@suggestion.new_value}
              class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-gray-300 rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
        </div>

        <div class="mt-3 grid grid-cols-[1fr_32px_1fr] items-start gap-6">
          <button type="button" class="text-xs text-[#00A1E0] hover:text-[#0082B4] font-medium justify-self-start">
            Update mapping
          </button>
          <span></span>
          <span :if={@suggestion[:timestamp]} class="text-xs text-slate-500 justify-self-start">Found in transcript<span
              class="text-[#00A1E0] hover:underline cursor-help"
              title={@suggestion[:context]}
            >
              ({@suggestion[:timestamp]})
            </span></span>
        </div>
      </div>
    </div>
    """
  end

end
