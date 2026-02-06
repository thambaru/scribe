defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates and formats Salesforce contact update suggestions by combining
  AI-extracted data with existing Salesforce contact information.
  """

  alias SocialScribe.Integrations.Suggestions
  alias SocialScribe.Integrations.Suggestions.SalesforceProvider
  alias SocialScribe.Accounts.UserCredential

  @doc """
  Generates suggested updates for a Salesforce contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the Salesforce field name
  - label: human-readable field label
  - current_value: the existing value in Salesforce (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default true)
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    Suggestions.generate_suggestions(SalesforceProvider, credential, contact_id, meeting)
  end

  @doc """
  Generates suggestions for a specific contact without re-fetching from Salesforce.
  Useful when contact data is already available.
  """
  def generate_suggestions_from_meeting(meeting, contact) do
    Suggestions.generate_suggestions_from_meeting(SalesforceProvider, meeting, contact)
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    Suggestions.merge_with_contact(SalesforceProvider, suggestions, contact)
  end
end
