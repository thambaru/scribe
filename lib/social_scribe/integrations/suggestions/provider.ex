defmodule SocialScribe.Integrations.Suggestions.Provider do
  @moduledoc false

  alias SocialScribe.Accounts.UserCredential

  @callback field_labels() :: map()
  @callback get_contact(UserCredential.t(), String.t()) :: {:ok, map()} | {:error, any()}
  @callback ai_suggestions(meeting :: map(), contact :: map() | nil) ::
              {:ok, list(map())} | {:error, any()}
  @callback get_contact_field(contact :: map(), field :: String.t()) :: any()
end

