defmodule SocialScribeWeb.MeetingLive.IntegrationModalComponent do
  @moduledoc false

  # Shared LiveComponent logic for integration modals (HubSpot/Salesforce).
  #
  # Elixir has no inheritance, so we use a `use` macro to share the common
  # update + event handler implementation while keeping provider-specific
  # rendering and message atoms in the concrete modules.
  defmacro __using__(opts) do
    search_message = Keyword.fetch!(opts, :search_message)
    generate_message = Keyword.fetch!(opts, :generate_message)
    apply_message = Keyword.fetch!(opts, :apply_message)

    quote do
      @integration_search_message unquote(search_message)
      @integration_generate_message unquote(generate_message)
      @integration_apply_message unquote(apply_message)

      @impl true
      def update(assigns, socket) do
        socket =
          socket
          |> assign(assigns)
          |> maybe_select_all_suggestions(assigns)
          |> assign_new(:step, fn -> :search end)
          |> assign_new(:query, fn -> "" end)
          |> assign_new(:contacts, fn -> [] end)
          |> assign_new(:selected_contact, fn -> nil end)
          |> assign_new(:suggestions, fn -> [] end)
          |> assign_new(:loading, fn -> false end)
          |> assign_new(:searching, fn -> false end)
          |> assign_new(:dropdown_open, fn -> false end)
          |> assign_new(:error, fn -> nil end)

        {:ok, socket}
      end

      defp maybe_select_all_suggestions(socket, %{suggestions: suggestions}) when is_list(suggestions) do
        assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
      end

      defp maybe_select_all_suggestions(socket, _assigns), do: socket

      @impl true
      def handle_event("contact_search", %{"value" => query}, socket) do
        query = String.trim(query)

        if String.length(query) >= 2 do
          socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
          send(self(), {@integration_search_message, query, socket.assigns.credential})
          {:noreply, socket}
        else
          {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
        end
      end

      @impl true
      def handle_event("open_contact_dropdown", _params, socket) do
        {:noreply, assign(socket, dropdown_open: true)}
      end

      @impl true
      def handle_event("close_contact_dropdown", _params, socket) do
        {:noreply, assign(socket, dropdown_open: false)}
      end

      @impl true
      def handle_event("toggle_contact_dropdown", _params, socket) do
        if socket.assigns.dropdown_open do
          {:noreply, assign(socket, dropdown_open: false)}
        else
          # When opening dropdown with selected contact, search for similar contacts
          socket = assign(socket, dropdown_open: true, searching: true)
          query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
          send(self(), {@integration_search_message, query, socket.assigns.credential})
          {:noreply, socket}
        end
      end

      @impl true
      def handle_event("select_contact", %{"id" => contact_id}, socket) do
        contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

        if contact do
          socket =
            assign(socket,
              loading: true,
              selected_contact: contact,
              error: nil,
              dropdown_open: false,
              query: "",
              suggestions: []
            )

          send(
            self(),
            {@integration_generate_message, contact, socket.assigns.meeting, socket.assigns.credential}
          )

          {:noreply, socket}
        else
          {:noreply, assign(socket, error: "Contact not found")}
        end
      end

      @impl true
      def handle_event("clear_contact", _params, socket) do
        {:noreply,
         assign(socket,
           step: :search,
           selected_contact: nil,
           suggestions: [],
           loading: false,
           searching: false,
           dropdown_open: false,
           contacts: [],
           query: "",
           error: nil
         )}
      end

      @impl true
      def handle_event("toggle_suggestion", params, socket) do
        applied_fields = Map.get(params, "apply", %{})
        values = Map.get(params, "values", %{})
        checked_fields = Map.keys(applied_fields)

        updated_suggestions =
          Enum.map(socket.assigns.suggestions, fn suggestion ->
            apply? = suggestion.field in checked_fields

            suggestion =
              case Map.get(values, suggestion.field) do
                nil -> suggestion
                new_value -> %{suggestion | new_value: new_value}
              end

            %{suggestion | apply: apply?}
          end)

        {:noreply, assign(socket, suggestions: updated_suggestions)}
      end

      @impl true
      def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
        socket = assign(socket, loading: true, error: nil)

        updates =
          selected
          |> Map.keys()
          |> Enum.reduce(%{}, fn field, acc ->
            Map.put(acc, field, Map.get(values, field, ""))
          end)

        send(
          self(),
          {@integration_apply_message, updates, socket.assigns.selected_contact, socket.assigns.credential}
        )

        {:noreply, socket}
      end

      @impl true
      def handle_event("apply_updates", _params, socket) do
        {:noreply, assign(socket, error: "Please select at least one field to update")}
      end

      @impl true
      def handle_event("toggle_details", %{"field" => field}, socket) do
        updated_suggestions =
          Enum.map(socket.assigns.suggestions, fn suggestion ->
            if suggestion.field == field do
              Map.put(suggestion, :hidden, !Map.get(suggestion, :hidden, false))
            else
              suggestion
            end
          end)

        {:noreply, assign(socket, suggestions: updated_suggestions)}
      end

      # Helper function to calculate selection counts for suggestions
      defp calculate_selection_counts(suggestions) do
        selected_count = Enum.count(suggestions, & &1.apply)
        object_count = if selected_count > 0, do: 1, else: 0
        integration_count = if selected_count > 0, do: 1, else: 0

        %{
          selected_count: selected_count,
          object_count: object_count,
          integration_count: integration_count
        }
      end
    end
  end
end
