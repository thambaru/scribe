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
    counts = calculate_selection_counts(assigns.suggestions)
    assigns = assign(assigns, counts)

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
              <.suggestion_card
                :for={suggestion <- @suggestions}
                suggestion={suggestion}
                target={@myself}
                theme={:salesforce}
                id_prefix="salesforce-suggestion"
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update Salesforce"
              submit_class="bg-[#00A1E0] hover:bg-[#0082B4]"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"#{@object_count} object, #{@selected_count} fields in #{@integration_count} integration selected to update"}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

end
