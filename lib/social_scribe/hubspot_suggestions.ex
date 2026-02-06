defmodule SocialScribe.HubspotSuggestions do
  @moduledoc """
  Generates and formats HubSpot contact update suggestions by combining
  AI-extracted data with existing HubSpot contact information.
  """

  alias SocialScribe.Integrations.Suggestions
  alias SocialScribe.Integrations.Suggestions.HubspotProvider
  alias SocialScribe.Accounts.UserCredential

  @doc """
  Generates suggested updates for a HubSpot contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the HubSpot field name
  - label: human-readable field label
  - current_value: the existing value in HubSpot (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default false)
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    Suggestions.generate_suggestions(HubspotProvider, credential, contact_id, meeting)
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when contact hasn't been selected yet.
  """
  def generate_suggestions_from_meeting(meeting) do
    Suggestions.generate_suggestions_from_meeting(HubspotProvider, meeting)
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    Suggestions.merge_with_contact(HubspotProvider, suggestions, contact)
  end
end
