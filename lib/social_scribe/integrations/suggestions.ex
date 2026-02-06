defmodule SocialScribe.Integrations.Suggestions do
  @moduledoc false

  alias SocialScribe.Accounts.UserCredential

  @type provider :: module()

  def generate_suggestions(provider, %UserCredential{} = credential, contact_id, meeting)
      when is_atom(provider) and is_binary(contact_id) and is_map(meeting) do
    with {:ok, contact} <- provider.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- provider.ai_suggestions(meeting, contact) do
      suggestions =
        ai_suggestions
        |> Enum.map(fn suggestion ->
          field = Map.get(suggestion, :field)
          current_value = provider.get_contact_field(contact, field)

          %{
            field: field,
            label: Map.get(provider.field_labels(), field, field),
            current_value: current_value,
            new_value: Map.get(suggestion, :value),
            context: Map.get(suggestion, :context),
            timestamp: Map.get(suggestion, :timestamp),
            apply: true,
            has_change: current_value != Map.get(suggestion, :value)
          }
        end)
        |> Enum.filter(& &1.has_change)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  # Meeting-only generation, optionally provider-specific depending on whether
  # the AI generator needs a contact context (Salesforce does).
  def generate_suggestions_from_meeting(provider, meeting, contact \\ nil)

  def generate_suggestions_from_meeting(provider, meeting, contact)
      when is_atom(provider) and is_map(meeting) do
    case provider.ai_suggestions(meeting, contact) do
      {:ok, ai_suggestions} ->
        suggestions =
          Enum.map(ai_suggestions, fn suggestion ->
            field = Map.get(suggestion, :field)

            %{
              field: field,
              label: Map.get(provider.field_labels(), field, field),
              current_value: nil,
              new_value: Map.get(suggestion, :value),
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def merge_with_contact(provider, suggestions, contact)
      when is_atom(provider) and is_list(suggestions) and is_map(contact) do
    Enum.map(suggestions, fn suggestion ->
      current_value = provider.get_contact_field(contact, suggestion.field)

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(& &1.has_change)
  end
end

