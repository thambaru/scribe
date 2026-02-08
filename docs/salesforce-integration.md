# Salesforce CRM Integration

Technical documentation for the Salesforce integration in SocialScribe. This integration allows users to connect their Salesforce account, search contacts after meetings, view AI-generated suggestions for updating contact fields based on meeting transcripts, and push selected updates back to Salesforce.

The implementation mirrors the existing HubSpot integration and shares infrastructure via macros and behaviours.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [File Map](#file-map)
- [OAuth Authentication](#oauth-authentication)
- [Database Schema](#database-schema)
- [Salesforce API Client](#salesforce-api-client)
- [Token Refresh System](#token-refresh-system)
- [AI Suggestion Pipeline](#ai-suggestion-pipeline)
- [LiveView UI Components](#liveview-ui-components)
- [Routing](#routing)
- [End-to-End Data Flow](#end-to-end-data-flow)
- [Environment Variables](#environment-variables)
- [Salesforce Connected App Setup](#salesforce-connected-app-setup)
- [Key Design Decisions](#key-design-decisions)
- [Extending the Integration](#extending-the-integration)

---

## Architecture Overview

```
                          +-----------------------+
                          |   Salesforce Cloud    |
                          |  (REST API v59.0)     |
                          +----------+------------+
                                     |
                          OAuth 2.0 / HTTPS
                                     |
+--------------------+    +----------v------------+    +---------------------+
|  Ueberauth OAuth   |--->|   SalesforceApi       |--->| SalesforceToken     |
|  Strategy           |   |   (Tesla HTTP client)  |   | Refresher           |
+--------------------+    +----------+------------+    +---------------------+
                                     |
                          +----------v------------+
                          |  SalesforceSuggestions |
                          |  + SalesforceProvider  |
                          +----------+------------+
                                     |
                          +----------v------------+
                          |  AI Content Generator  |
                          |  (Gemini API)          |
                          +----------+------------+
                                     |
                          +----------v------------+
                          |  LiveView Components   |
                          |  (Modal + Meeting Show)|
                          +------------------------+
```

---

## File Map

### Created Files

| File | Purpose |
|------|---------|
| `lib/ueberauth/strategy/salesforce.ex` | Ueberauth strategy - handles OAuth request/callback lifecycle |
| `lib/ueberauth/strategy/salesforce/oauth.ex` | OAuth2 client - token exchange, user info fetching |
| `lib/social_scribe/salesforce_api.ex` | REST API client - contact search, get, update |
| `lib/social_scribe/salesforce_api_behaviour.ex` | Behaviour module for mocking in tests |
| `lib/social_scribe/salesforce_token_refresher.ex` | Token refresh logic and expiration handling |
| `lib/social_scribe/workers/salesforce_token_refresher.ex` | Oban cron worker for proactive token refresh |
| `lib/social_scribe/salesforce_suggestions.ex` | Suggestion generation orchestrator |
| `lib/social_scribe/integrations/suggestions/salesforce_provider.ex` | Provider behaviour impl - field labels, contact mapping |
| `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex` | LiveView modal for contact search and update UI |
| `priv/repo/migrations/20250526000001_add_metadata_to_user_credentials.exs` | Adds `metadata` map field to `user_credentials` |

### Modified Files

| File | Changes |
|------|---------|
| `config/config.exs` | Added Salesforce Ueberauth provider + Oban cron job |
| `config/runtime.exs` | Salesforce OAuth client_id/secret from env vars |
| `lib/social_scribe/accounts.ex` | `get_user_salesforce_credential/1`, `find_or_create_salesforce_credential/2` |
| `lib/social_scribe/accounts/user_credential.ex` | Added `:metadata` field to schema |
| `lib/social_scribe/ai_content_generator.ex` | Added `generate_salesforce_suggestions/2` |
| `lib/social_scribe/ai_content_generator_api.ex` | Added Salesforce suggestions callback |
| `lib/social_scribe_web/router.ex` | Added `/meetings/:id/salesforce` live route |
| `lib/social_scribe_web/controllers/auth_controller.ex` | Salesforce OAuth callback handler |
| `lib/social_scribe_web/live/user_settings_live.ex` | Loads `salesforce_accounts` on mount |
| `lib/social_scribe_web/live/user_settings_live.html.heex` | Salesforce connection UI section |
| `lib/social_scribe_web/live/meeting_live/show.ex` | Salesforce credential assign + event handlers |
| `lib/social_scribe_web/live/meeting_live/show.html.heex` | "Update Salesforce Contact" button + modal |

---

## OAuth Authentication

### Strategy: `Ueberauth.Strategy.Salesforce`

The OAuth flow uses the standard Ueberauth pattern with two modules:

#### OAuth2 Client (`lib/ueberauth/strategy/salesforce/oauth.ex`)

Configures the OAuth2 endpoints:

| Setting | Value |
|---------|-------|
| Site | `https://login.salesforce.com` |
| Authorize URL | `https://login.salesforce.com/services/oauth2/authorize` |
| Token URL | `https://login.salesforce.com/services/oauth2/token` |

Key method: `get_access_token/2` exchanges the authorization code for an access token. The token response from Salesforce includes `instance_url` in `other_params`, which is critical for all subsequent API calls since each Salesforce org has a unique instance URL (e.g., `https://na1.salesforce.com`).

After obtaining the token, `get_user_info/2` fetches the user identity from the `id` URL included in the token response. This uses a separate Tesla HTTP call (not the OAuth2 client) because the `id` URL is a full absolute URL, not relative to the token endpoint.

#### Strategy (`lib/ueberauth/strategy/salesforce.ex`)

Configuration:

- **UID field:** `organization_id` (from user info response) - identifies the Salesforce org, not the individual user
- **Default scope:** `api refresh_token`
- **Credentials:** Extracts `instance_url` into `credentials.other.instance_url`

#### Auth Controller Callback (`lib/social_scribe_web/controllers/auth_controller.ex`)

When the callback arrives with `provider: "salesforce"`:

1. Extracts `instance_url` from `auth.credentials.other.instance_url`
2. Calls `Accounts.find_or_create_salesforce_credential/2` with:
   - `provider: "salesforce"`
   - `uid: auth.uid` (organization_id)
   - `token: auth.credentials.token`
   - `refresh_token: auth.credentials.refresh_token`
   - `email: auth.info.email`
   - `expires_at:` calculated as `now + 7200 seconds` (2 hours)
   - `metadata: %{"instance_url" => instance_url}`
3. Redirects to settings page with success/error flash

---

## Database Schema

### `user_credentials` Table

The `UserCredential` schema (`lib/social_scribe/accounts/user_credential.ex`) stores OAuth credentials for all providers (HubSpot, Salesforce, etc.):

```elixir
schema "user_credentials" do
  field :token, :string              # OAuth access token
  field :uid, :string                # Provider-specific ID (organization_id for Salesforce)
  field :provider, :string           # "salesforce" | "hubspot"
  field :refresh_token, :string      # OAuth refresh token
  field :expires_at, :utc_datetime   # Token expiration timestamp
  field :email, :string              # User's email from provider
  field :metadata, :map, default: %{}  # Provider-specific data
  belongs_to :user, SocialScribe.Accounts.User
end
```

For Salesforce, `metadata` stores:

```json
{
  "instance_url": "https://yourorg.my.salesforce.com"
}
```

The `instance_url` is essential because Salesforce API endpoints are instance-specific. Without it, no API calls can be made.

### Relevant Account Functions (`lib/social_scribe/accounts.ex`)

- `get_user_salesforce_credential(user_id)` - Fetches the user's Salesforce credential
- `find_or_create_salesforce_credential(user, attrs)` - Upserts credential by user + provider
- `list_user_credentials(user, provider: "salesforce")` - Lists all Salesforce connections for a user

---

## Salesforce API Client

### Module: `SocialScribe.SalesforceApi`

**File:** `lib/social_scribe/salesforce_api.ex`

Uses Tesla HTTP client with dynamic base URL constructed from the credential's `instance_url`:

```
Base URL: {instance_url}/services/data/v59.0
Auth Header: Bearer {access_token}
```

### Contact Fields

The API fetches these 14 fields (plus nested `Account.Name`):

```
Id, FirstName, LastName, Email, Phone, MobilePhone, Title, Department,
MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
Account.Name
```

### Functions

#### `search_contacts(credential, query)`

Searches contacts using SOSL (Salesforce Object Search Language):

```
FIND {escaped_query} IN ALL FIELDS RETURNING Contact(fields) LIMIT 10
```

- Escapes 15 special SOSL characters to prevent injection
- Returns up to 10 contacts formatted as maps with snake_case atom keys
- Handles both `searchRecords` and list response formats

#### `get_contact(credential, contact_id)`

Fetches a single contact:

```
GET /sobjects/Contact/{id}?fields={comma_separated_fields}
```

#### `update_contact(credential, contact_id, updates)`

Updates contact fields:

```
PATCH /sobjects/Contact/{id}
Body: {field_name: value, ...}
```

Returns 204 No Content on success. After a successful update, re-fetches and returns the updated contact.

#### `apply_updates(credential, contact_id, updates_list)`

Convenience wrapper that:
1. Filters the list for entries where `apply: true`
2. Converts to a field-value map
3. Calls `update_contact/3`

### Contact Data Format

The API normalizes Salesforce responses into a flat map:

```elixir
%{
  id: "003XX0000012345",
  firstname: "John",
  lastname: "Doe",
  email: "john@example.com",
  phone: "555-1234",
  mobilephone: "555-9876",
  title: "Manager",
  department: "Sales",
  mailing_street: "123 Main St",
  mailing_city: "San Francisco",
  mailing_state: "CA",
  mailing_postal_code: "94102",
  mailing_country: "USA",
  company: "Acme Corp",       # Extracted from nested Account.Name
  display_name: "John Doe"    # Computed from FirstName + LastName, fallback to Email
}
```

### Token Refresh Wrapper

Every API function is wrapped in `with_token_refresh/2`:

1. Calls `SalesforceTokenRefresher.ensure_valid_token/1` (pre-emptive check)
2. Executes the API call
3. On 401 or token errors (INVALID_SESSION_ID, INVALID_AUTH_HEADER, invalid_grant, etc.): refreshes token and retries once
4. On second failure: returns error

---

## Token Refresh System

### Module: `SocialScribe.SalesforceTokenRefresher`

**File:** `lib/social_scribe/salesforce_token_refresher.ex`

#### `refresh_token(refresh_token_string)`

Posts to `https://login.salesforce.com/services/oauth2/token` with:

```
grant_type=refresh_token
client_id={from config}
client_secret={from config}
refresh_token={refresh_token_string}
```

Important: Salesforce may not return a new refresh_token. The original one remains valid until explicitly revoked.

#### `refresh_credential(credential)`

1. Calls `refresh_token/1`
2. Calculates `expires_at`:
   - If response includes `issued_at` (milliseconds since epoch): converts to DateTime + 7200 seconds
   - Otherwise: `now + 7200 seconds`
3. Updates `instance_url` in metadata if the response contains a new one
4. Preserves the existing refresh_token if Salesforce doesn't return a new one
5. Persists via `Accounts.update_user_credential/2`

#### `ensure_valid_token(credential)`

Pre-emptive check called before every API request:

- If token expires within **300 seconds (5 minutes)**: refreshes immediately
- Otherwise: returns credential as-is

### Oban Worker: `SocialScribe.Workers.SalesforceTokenRefresher`

**File:** `lib/social_scribe/workers/salesforce_token_refresher.ex`

- Runs every **5 minutes** via Oban cron (`"*/5 * * * *"`)
- Uses the `ProactiveOAuthTokenRefresher` macro with `provider: "salesforce"`
- Queries all Salesforce credentials expiring within **10 minutes**
- Refreshes each one proactively to prevent expiration during active use

---

## AI Suggestion Pipeline

The suggestion system analyzes meeting transcripts and suggests Salesforce contact field updates.

### Flow

```
Meeting Transcript
       |
       v
AIContentGenerator.generate_salesforce_suggestions(meeting, contact)
       |  (Gemini API call with structured prompt)
       v
Raw suggestions: [{field, value, context, timestamp}, ...]
       |
       v
SalesforceSuggestions.merge_with_contact(suggestions, contact)
       |  (Adds current_value, label, apply flag)
       v
Merged suggestions shown in UI
```

### AI Content Generator (`lib/social_scribe/ai_content_generator.ex`)

`generate_salesforce_suggestions(meeting, contact)`:

- Sends the meeting transcript to the Gemini API
- Prompt explicitly names the target contact to avoid mixing data from other meeting participants
- Requests only explicitly stated information (no inference)
- Returns JSON array of suggestions with:
  - `field`: Salesforce API field name (e.g., "MobilePhone")
  - `value`: Extracted value
  - `context`: Quote from transcript
  - `timestamp`: When mentioned

### Salesforce Provider (`lib/social_scribe/integrations/suggestions/salesforce_provider.ex`)

Implements the `Suggestions.Provider` behaviour:

- **`field_labels/0`** - Maps 24 Salesforce field names to human-readable labels
- **`get_contact/2`** - Delegates to `SalesforceApi.get_contact/2`
- **`ai_suggestions/2`** - Delegates to `AIContentGeneratorApi.generate_salesforce_suggestions/2`
- **`get_contact_field/2`** - Looks up contact field value using the `@field_to_key` mapping

The `@field_to_key` map converts Salesforce PascalCase field names to the snake_case atom keys used in the formatted contact map:

```elixir
"FirstName"        => :firstname
"MobilePhone"      => :mobilephone
"MailingPostalCode" => :mailing_postal_code
# etc.
```

### Suggestions Orchestrator (`lib/social_scribe/salesforce_suggestions.ex`)

Thin wrapper delegating to the shared `Suggestions` module:

- `generate_suggestions(credential, contact_id, meeting)` - Full flow: fetch contact + AI + merge
- `generate_suggestions_from_meeting(meeting, contact)` - Skips contact fetch (already have data)
- `merge_with_contact(suggestions, contact)` - Compares current vs. suggested values

---

## LiveView UI Components

### Shared Logic: `IntegrationModalComponent`

**File:** `lib/social_scribe_web/live/meeting_live/integration_modal_component.ex`

A `use` macro that injects common LiveComponent logic for both HubSpot and Salesforce modals. This avoids code duplication since Elixir doesn't support inheritance.

The macro accepts three message atoms that customize the provider-specific messages sent to the parent LiveView:

```elixir
use IntegrationModalComponent,
  search_message: :salesforce_search,
  generate_message: :generate_salesforce_suggestions,
  apply_message: :apply_salesforce_updates
```

#### Shared State

| Assign | Type | Description |
|--------|------|-------------|
| `step` | atom | `:search` or `:suggestions` |
| `query` | string | Current search input |
| `contacts` | list | Search results |
| `selected_contact` | map/nil | Chosen contact |
| `suggestions` | list | AI-generated suggestions |
| `loading` | boolean | Suggestion generation / update in progress |
| `searching` | boolean | Contact search in progress |
| `dropdown_open` | boolean | Contact dropdown visibility |
| `error` | string/nil | Error message |

#### Events Handled

| Event | Trigger | Action |
|-------|---------|--------|
| `contact_search` | Text input (2+ chars) | Sends search message to parent |
| `select_contact` | Click contact in dropdown | Sends generate message to parent |
| `clear_contact` | Clear selection | Resets to search step |
| `toggle_suggestion` | Checkbox change | Toggles `apply` flag on suggestion |
| `apply_updates` | Form submit | Sends apply message to parent |
| `toggle_details` | Click expand | Toggles suggestion context visibility |
| `toggle_field_mapping` | Click "Update mapping" | Opens field selector dropdown |
| `change_suggestion_field` | Select field from dropdown | Updates suggestion's field and label |
| `close_field_mapping` | Click outside dropdown | Closes field selector dropdown |
| `open/close/toggle_contact_dropdown` | UI interactions | Controls dropdown state |

#### Manual Field Selection

Users can override the AI's field mapping if it incorrectly identifies which CRM field to update:

**User Flow:**
1. AI suggests updating a field (e.g., "Email" → "john@example.com")
2. User clicks "Update mapping" link below the suggestion
3. Dropdown appears showing all available CRM fields
4. User selects correct field (e.g., "Mobile Phone")
5. Suggestion updates with new field name and label, keeping the suggested value
6. User submits form with corrected mapping

**Implementation:**

- Each `suggestion_card` receives `available_fields` map from the provider's `field_labels/0`
- Dropdown excludes the currently selected field
- `change_suggestion_field` event updates the suggestion's `field` and `label` in state
- The form submission uses the updated field name when applying updates
- State tracking: `field_mapping_hidden` boolean on each suggestion controls dropdown visibility

**Helper Function:**

`get_field_labels(socket)` - Detects provider (HubSpot/Salesforce) from socket context and returns the appropriate field labels map for the dropdown options.

### Salesforce Modal (`lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex`)

Renders the Salesforce-branded UI:

- Title: "Update in Salesforce"
- Submit button: "Update Salesforce" with Salesforce blue (`#00A1E0`)
- Uses shared `contact_select` and `suggestion_card` components
- Theme: `:salesforce` passed to suggestion cards
- Available fields: Passes `SalesforceProvider.field_labels()` (24 fields) to each suggestion card

### Meeting Show Page Handlers (`lib/social_scribe_web/live/meeting_live/show.ex`)

The parent LiveView handles three messages from the modal component:

#### `:salesforce_search`
```
receive query + credential
  -> SalesforceApi.search_contacts(credential, query)
  -> send_update(SalesforceModalComponent, contacts: results)
```

#### `:generate_salesforce_suggestions`
```
receive contact + meeting + credential
  -> SalesforceSuggestions.generate_suggestions_from_meeting(meeting, contact)
  -> send_update(SalesforceModalComponent, suggestions: merged_results)
```

#### `:apply_salesforce_updates`
```
receive updates + contact + credential
  -> SalesforceApi.update_contact(credential, contact.id, updates)
  -> Flash "Successfully updated X field(s) in Salesforce"
  -> Redirect to meeting page
```

---

## Routing

**File:** `lib/social_scribe_web/router.ex`

### OAuth Routes (unauthenticated)

```
GET /auth/salesforce          -> AuthController.request   (initiates OAuth)
GET /auth/salesforce/callback -> AuthController.callback  (handles OAuth callback)
```

These use the generic `/:provider` pattern shared with HubSpot.

### Meeting Routes (authenticated)

```
GET /meetings/:id             -> MeetingLive.Show, :show        (meeting detail)
GET /meetings/:id/salesforce  -> MeetingLive.Show, :salesforce  (opens Salesforce modal)
```

The `:salesforce` live action triggers conditional rendering of the Salesforce modal in the meeting show template.

### Settings Route (authenticated)

The settings page at `/settings` loads Salesforce accounts on mount via `Accounts.list_user_credentials(current_user, provider: "salesforce")`.

---

## End-to-End Data Flow

### 1. Connecting Salesforce (Settings Page)

```
User clicks "Connect Salesforce"
  -> GET /auth/salesforce
  -> Ueberauth redirects to Salesforce login
  -> User authenticates and grants permissions
  -> Salesforce redirects to /auth/salesforce/callback?code=xxx
  -> AuthController extracts token + instance_url
  -> Stores UserCredential (provider: "salesforce", metadata: {instance_url})
  -> Redirects to /settings with success flash
```

### 2. Searching Contacts (Meeting Page)

```
User opens /meetings/:id/salesforce (modal appears)
  -> Types contact name in search input
  -> IntegrationModalComponent sends :salesforce_search to parent
  -> MeetingLive.Show calls SalesforceApi.search_contacts/2
  -> SOSL query: FIND {name} IN ALL FIELDS RETURNING Contact(...)
  -> Results sent back to modal via send_update
  -> Contacts displayed in dropdown
```

### 3. Generating Suggestions

```
User selects a contact from dropdown
  -> IntegrationModalComponent sends :generate_salesforce_suggestions to parent
  -> MeetingLive.Show calls SalesforceSuggestions.generate_suggestions_from_meeting/2
  -> SalesforceProvider.ai_suggestions/2 sends transcript to Gemini
  -> AI returns structured field suggestions
  -> Suggestions merged with current contact values
  -> Merged suggestions sent to modal via send_update
  -> Suggestion cards rendered with checkboxes
```

### 4. Applying Updates

```
User checks desired fields and clicks "Update Salesforce"
  -> IntegrationModalComponent sends :apply_salesforce_updates to parent
  -> MeetingLive.Show calls SalesforceApi.update_contact/3
  -> PATCH /sobjects/Contact/{id} with selected field values
  -> On 204 success: flash "Successfully updated X field(s)"
  -> Modal closes, redirects to meeting page
```

---

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SALESFORCE_CLIENT_ID` | Connected App Consumer Key | `3MVG9...` |
| `SALESFORCE_CLIENT_SECRET` | Connected App Consumer Secret | `ABC123...` |
| `SALESFORCE_REDIRECT_URI` | OAuth callback URL (optional, constructed from app URL if not set) | `http://localhost:4000/auth/salesforce/callback` |

These are read in `config/runtime.exs`:

```elixir
config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
  client_id: System.get_env("SALESFORCE_CLIENT_ID"),
  client_secret: System.get_env("SALESFORCE_CLIENT_SECRET"),
  redirect_uri: System.get_env("SALESFORCE_REDIRECT_URI")
```

---

## Salesforce Connected App Setup

To use this integration, a Salesforce Connected App must be configured:

1. Log into Salesforce Setup
2. Navigate to **App Manager** > **New Connected App**
3. Fill in basic info (Connected App Name, API Name, Contact Email)
4. Under **API (Enable OAuth Settings)**:
   - Check "Enable OAuth Settings"
   - **Callback URL:** `http://localhost:4000/auth/salesforce/callback` (dev) or your production URL
   - **Selected OAuth Scopes:**
     - `Access the identity URL service (id, profile, email, address, phone)`
     - `Manage user data via APIs (api)`
     - `Perform requests at any time (refresh_token, offline_access)`
5. Save and wait for activation (can take 2-10 minutes)
6. Note the **Consumer Key** (client_id) and **Consumer Secret** (client_secret)

---

## Key Design Decisions

### Why `organization_id` as UID (not `user_id`)

Salesforce's organization_id identifies the Salesforce org. This was chosen because:
- A single Salesforce org may have multiple users
- The credential represents the org-level connection
- Prevents duplicate connections to the same org

### Why `metadata` Map Instead of Dedicated Columns

The `instance_url` is stored in a generic `metadata` JSON field rather than a dedicated column because:
- Only Salesforce needs `instance_url` (HubSpot doesn't)
- The map is extensible for future provider-specific data
- Avoids schema migrations for every new provider field

### Why SOSL Instead of SOQL for Search

SOSL (Salesforce Object Search Language) is used for contact search instead of SOQL because:
- SOSL searches across all text fields simultaneously
- Better fuzzy matching for name searches
- SOQL `LIKE` would require knowing which specific field to search

### Shared IntegrationModalComponent Macro

The modal logic is shared via a `__using__` macro rather than duplicated because:
- HubSpot and Salesforce modals have identical interaction patterns
- Only the message atoms and branding differ
- Keeps UI behaviour consistent across integrations
- Adding a new CRM only requires defining render + 3 message atoms

---

## Extending the Integration

### Adding New Contact Fields

1. Add the field to `@contact_fields` in `SalesforceApi`
2. Add the mapping in `format_contact/1` in `SalesforceApi`
3. Add labels in `@field_labels` in `SalesforceProvider`
4. Add key mapping in `@field_to_key` in `SalesforceProvider`

### Adding a New CRM Integration

Follow the same pattern:

1. Create Ueberauth strategy (`lib/ueberauth/strategy/{provider}.ex` + `oauth.ex`)
2. Create API client (`lib/social_scribe/{provider}_api.ex` + behaviour)
3. Create token refresher (`lib/social_scribe/{provider}_token_refresher.ex` + worker)
4. Create provider (`lib/social_scribe/integrations/suggestions/{provider}_provider.ex`)
   - Must implement `field_labels/0` to return a map of field keys to human-readable labels
   - This map is used for the manual field mapping dropdown
5. Create suggestions module (`lib/social_scribe/{provider}_suggestions.ex`)
6. Create modal component using `IntegrationModalComponent`:
   ```elixir
   use IntegrationModalComponent,
     search_message: :{provider}_search,
     generate_message: :generate_{provider}_suggestions,
     apply_message: :apply_{provider}_updates
   
   # In render function, pass available_fields to suggestion_card:
   <.suggestion_card
     :for={suggestion <- @suggestions}
     suggestion={suggestion}
     target={@myself}
     available_fields={YourProvider.field_labels()}
   />
   ```
7. Add handlers in `MeetingLive.Show` for the three messages
8. Add routes, config, and environment variables

**Note:** The `available_fields` attribute is required for the manual field selection feature. It populates the dropdown that allows users to correct AI field mapping errors.

### Testing with Mocks

The `SalesforceApiBehaviour` module enables testing without live Salesforce calls. Configure your test environment to use a mock module implementing the behaviour.
