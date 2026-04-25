# Apple Authentication Plan

This document is the implementation plan for adding **Sign in with Apple** to Desolate Frontiers, aligned with the existing identity architecture (APICalls → Services → Store/Hub → UI) and current provider patterns (Discord + Steam).

## 1) Goals

- Add Apple as a first-class auth provider for:
  - New login
  - Existing-account linking
  - Conflict/merge flow parity with Steam/Discord
- Reuse as much existing auth infrastructure as possible:
  - `auth/status` polling
  - session token persistence in `user://session.cfg`
  - `/auth/me` identity resolution
  - merge preview/commit transport
- Keep UX consistent and safe:
  - clear status messages
  - robust error handling
  - no regressions in Steam/Discord flows

---

## 2) Current System Snapshot (what we are building on)

From current implementation:

- `APICalls` already supports:
  - provider URL start + auth status polling (`get_auth_url()` + `start_auth_poll()`)
  - direct token-style login (`login_with_steam()`)
  - account linking + merge (`link_steam_account()`, `get_discord_link_url()`, `preview_merge()`, `commit_merge()`)
- `LoginScreen` already supports:
  - Discord browser OAuth launch and status handling
  - Steam direct login
  - canonical auth state updates from `SignalHub`
- Session model already exists and should remain unchanged:
  - JWT storage
  - expiry checks
  - `/auth/me` → `user_id`

Apple should fit into this model, not create a parallel auth stack.

---

## 3) Recommended Delivery Strategy

Deliver in two phases:

### Phase A (fastest path): Browser-based Apple OAuth via existing poll flow

Use the current Discord-style flow pattern:

1. Client requests provider auth URL (`apple`).
2. Browser opens Apple sign-in page.
3. Backend callback updates auth state.
4. Client polls `/auth/status?state=...` until complete.
5. Backend returns session token; client stores token and resolves user via `/auth/me`.

Why this first:
- Minimal client-side platform-specific code.
- Reuses proven queue/poll/session logic.
- Works on desktop targets quickly.

### Phase B (optional hardening): Native Apple sign-in on iOS/macOS

Add native provider flow later for better platform UX and policy fit, while still exchanging resulting Apple tokens with your backend and reusing the same DF session issuance.

---

## 4) Apple Developer Setup (external prerequisites)

Before coding client flow, complete Apple configuration:

1. **App ID capability**
	- Enable “Sign in with Apple” on the game App ID.

2. **Service ID (for web OAuth flow)**
	- Create Service ID used as OAuth client identifier.
	- Configure callback/redirect URL(s) used by backend.

3. **Key for Sign in with Apple**
	- Create private key (`.p8`) for token exchange.
	- Record `Key ID`, `Team ID`, `Client ID`.

4. **Email relay (if used)**
	- Configure relay domain/sender if backend emails users.

5. **Environment split**
	- Separate dev/staging/prod credentials and callback URLs.

---

## 5) Backend API Contract Plan

Use provider-consistent contracts so the Godot client can stay thin.

### Login

- `GET /auth/apple/url` (or generalized `/auth/url?provider=apple`)
  - Returns `{ url, state }`
- Existing `GET /auth/status?state=...`
  - Returns pending/complete/error + session token on success

### Linking

- `GET /auth/apple/link/url`
  - Returns `{ url, state }` for linking current authenticated DF account
- Existing `GET /auth/status?state=...`
  - On success: indicate linked result
  - On conflict: return `409` semantics + `merge_token` + conflict payload

### Merge (reuse existing)

- `POST /auth/merge/preview`
- `POST /auth/merge/commit`

No Apple-specific merge endpoints are needed if conflict payload shape is consistent.

### Validation requirements on backend

- Verify Apple identity token signature via Apple JWKS.
- Validate claims:
  - `iss` = Apple issuer
  - `aud` = expected client/service id
  - `exp`/`iat`
  - `nonce` (if used)
- Use Apple `sub` as stable provider subject key.
- Persist first-returned email/name safely (Apple may only send once).

---

## 6) Godot Client Changes

## 6.1 `APICalls` changes

1. **Generalize provider URL call**
	- Update `get_auth_url(_provider: String = "")` so provider is used (not ignored).
	- Route Discord to current endpoint and Apple to Apple endpoint.

2. **Add Apple link transport methods**
	- `get_apple_link_url()` similar to `get_discord_link_url()`.
	- Add signal(s), e.g.:
	  - `apple_link_url_received(url, state)`
	  - `apple_account_linked(result)`

3. **Auth status completion mapping**
	- In `AUTH_STATUS` handling, map Apple link completion/errors similarly to current Discord link handling.
	- Preserve `409` conflict extraction (`conflict`, `merge_token`) so merge UI remains provider-agnostic.

4. **Do not change session mechanics**
	- Keep `set_auth_session_token()`, `resolve_current_user_id()`, `/auth/me` flow identical.

## 6.2 `LoginScreen` changes

1. Add **Continue with Apple** button (active or “coming soon” depending on feature flag).
2. On press:
	- call `api.get_auth_url("apple")`
	- open returned URL via `OS.shell_open()`
	- rely on existing polling status messaging.
3. Update UX copy:
	- “Opening Apple sign-in…” / “Complete Apple sign-in in your browser…”
4. Keep spinner/disabled states consistent with existing OAuth behavior.

## 6.3 Account settings / link UI changes

Where provider linking is surfaced:

- Add “Link Apple account” action.
- Start Apple link URL flow.
- Handle link success, normal failures, and conflict (`409`) exactly like Steam/Discord.
- Reuse existing merge modal and post-merge refresh path.

---

## 7) Data Model & Event Consistency

Keep user model backward compatible:

- Continue using `/auth/links` as source of truth for linked identities.
- If top-level convenience fields exist (`steam_id`, `discord_id`), consider adding `apple_sub` or `apple_id` only if needed by existing UI logic.
- Prefer provider-agnostic link objects:
  - `{ provider, provider_subject_id, linked_at }`

Signals/events:

- Preserve canonical `auth_state_changed(state)` usage.
- Emit provider-specific link result signals only at transport edges.
- Keep `user_changed(user)` as final source for UI data refresh.

---

## 8) Security & Compliance Checklist

- Never store Apple private keys in client.
- Backend-only Apple token exchange and validation.
- Protect against replay:
  - use/validate `state`
  - use nonce where applicable
- Use short-lived auth state records.
- Log minimal PII.
- Respect Apple private relay emails and account deletion/unlink requirements.

---

## 9) Testing Plan

## 9.1 Unit / transport tests

Add/extend tests around `APICalls`:

- Apple auth URL request success/failure.
- Apple auth status transitions: pending → complete/error/denied/cancelled.
- Apple link success.
- Apple link conflict 409 emits merge payload correctly.
- Session token persistence unchanged.

Likely locations:

- `Tests/test_api_calls.gd`
- new `Tests/test_apple_auth.gd` (recommended)

## 9.2 UI behavior tests

- Login button disabled while auth in progress.
- Correct status copy updates.
- Authenticated state still transitions to main flow.
- Failure states clear spinner and show actionable message.

## 9.3 Manual end-to-end matrix

1. New user logs in with Apple.
2. Existing Steam user links Apple.
3. Existing Discord user links Apple.
4. Apple identity already linked elsewhere → merge preview/commit.
5. Cancel/denied flow from Apple.
6. Session restore on app restart after Apple login.

---

## 10) Rollout Plan

1. **Feature flag**
	- Add `auth.apple_enabled` (config/env controlled).
	- Hide/disable Apple button when off.

2. **Soft launch**
	- Dev/staging only first.
	- Verify backend callback + polling stability.

3. **Production ramp**
	- Enable for a subset or by platform first (macOS/iOS).
	- Monitor auth success %, timeout rate, conflict rate.

4. **Post-launch cleanup**
	- Normalize provider handling where duplicated.
	- Optionally migrate to fully generic provider dispatch in APICalls.

---

## 11) Implementation Task Breakdown (execution checklist)

### Backend
- [ ] Create Apple OAuth endpoints (login + link URL).
- [ ] Wire callback to existing auth state store.
- [ ] Return consistent status payloads and 409 conflict envelopes.
- [ ] Validate Apple tokens (JWKS, claims, nonce/state).
- [ ] Issue DF session tokens exactly as current providers do.

### Client transport (`APICalls`)
- [ ] Use provider argument in `get_auth_url()`.
- [ ] Add Apple link request method + completion handler.
- [ ] Add Apple link result signal(s).
- [ ] Extend auth-status branch to emit Apple link outcomes.
- [ ] Keep session + `/auth/me` flow unchanged.

### Client UI
- [ ] Add Apple login button and styling.
- [ ] Hook button to Apple auth URL flow.
- [ ] Add Apple link UI action in account settings.
- [ ] Reuse existing merge modal for Apple conflicts.

### QA
- [ ] Add automated tests for Apple auth/link/conflict.
- [ ] Run full provider regression (Discord + Steam + Apple).
- [ ] Validate macOS App Store build behavior.

---

## 12) Definition of Done

Apple auth is complete when all are true:

1. User can sign in with Apple and reach game with valid session.
2. Existing account can link Apple identity.
3. Conflict path provides merge preview/commit and resolves correctly.
4. Session restore works after restart.
5. Discord/Steam flows are unaffected.
6. Auth errors are user-readable and logged for diagnosis.

