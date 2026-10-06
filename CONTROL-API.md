# 13 Years Control API

## What This Is

An HTTP + WebSocket API embedded in the Producer app (macOS and iPad) so that a Stream Deck, Bitfocus Companion, QLab, a lighting console, or a shell script can drive the show. Every route resolves to a method the app's own buttons already call — a cue fired remotely and a cue fired on screen take the identical path through `CueEngine`. That path is singular: same persistence, same broadcast to pagers over LAN/relay/peer, same Planning Center Live mirroring. The API is not a wrapper around show state; it is a second door onto the engine that is the only source of truth.

## Getting Connected

Off by default; enabled in the Producer app's Settings → Control API. The exact base URLs (including this device's LAN addresses) are displayed there so a control surface can find and reach the producer without typing or hunting.

**Default port:** 13390 (sits beside the LAN cue port 13380 and the producer-assign port 13381, so every fixed port this app claims lives in the same numeric neighbourhood).

**Discovery:** served via the producer's `_13years._tcp` service — the same Bonjour registration every pager already finds. Its TXT record carries the producer's IPv4 (`ip=`) and this API's actual port (`apiport=`), so a control surface that can browse the pager channel already has everything it needs to reach the API. There is deliberately no *separate* Bonjour service for the API: macOS can refuse an extra registration (a `NoAuth` DNS error) even with the type declared in `Info.plist`, and `NWListener` reports that refusal by failing the entire listener — so a discovery nicety could take the working socket down with it. The API is always there on its port and the IP-based URLs in Settings still work — which is how most control surfaces are configured anyway.

**Base URL:** `http://<device>:13390/v1`

**Web pager:** `http://<device>:13390/pager` — a browser pager served off this same listener, and the only path outside `/v1`. See [The Web Pager](#the-web-pager).

## No Authentication

There is no bearer token, no API key, no credential of any kind. Anyone who can reach the port can fire a cue or clear the plan. That is a deliberate choice for a trusted production LAN, which is why the server ships disabled and is enabled per-device in Settings. Leave it off on guest or venue Wi-Fi that other people share. There is a single seam — the `authorize(_:)` function in `ControlAPIServer.swift` — where an authentication check would live if the decision changes. Adding one later would be a function body, not a refactor through every route.

## Conventions

**JSON in, JSON out.** Dates are ISO-8601 strings. Most mutating routes return the full state snapshot, so a client rarely needs a follow-up read.

**202 Accepted:** Routes whose real work happens asynchronously (Planning Center fetches, pairing handshakes, live-control synchronization) return 202 with the current state snapshot. The result shows up in a later `state` event on the WebSocket, not in this reply.

**409 Conflict** means the request was understood but the app isn't in a state to serve it — no plan loaded when you drive the timer, or no role currently selected when you fire `POST /v1/cues/selected`. That last one is worth knowing about: `selectedRoleIds` is not persisted across launches, so on a fresh launch it holds the fresh-install default, which matches nothing once a producer has renamed or replaced the starter role. Set the selection first with `PUT /v1/selection`. The API answers 409 rather than a silent 200 precisely so a dead cue can't be mistaken for a live one.

**Error bodies** are `{"error": "message", "detail": "more context"}` — an integrator can read `error` for a display or log, and `detail` for debugging.

**Setters are absolute, never toggles.** Every route that changes a boolean takes the value it should end up at (`{"isActual": true}`, `{"enabled": false}`, `{"isMaster": true}`), not a "flip it" instruction. That makes a repeated press idempotent — a macro pad that fires twice, or two control surfaces pressing at once, converge instead of fighting — and it means a route's effect doesn't depend on state the caller can't see. A *toggle* is a client-side concern: read the current value from the state snapshot, send its inverse. The Companion module builds all of its toggle buttons that way rather than asking for toggle routes.

**Projected/Actual exists at two levels, and they are not the same control.** `POST /v1/plan/items/{id}/duration-actual` sets the plan item's own persisted `isDurationActual` — the item's real duration type, which survives into the next time that plan loads. `POST /v1/timer/actual-override` sets a transient override for whatever item is live, deliberately never written into the plan, and it goes stale the moment a different item becomes active. Use the first for "this song is genuinely 4:32"; use the second for "the stream is on a five-minute delay today." Read the displayed result from `timer.isDurationActualForDisplay`, which already folds the override over the plan's value — a client toggling against the plan item's raw flag will look like it does nothing on the first press whenever an override is in force.

**CORS is open** (`Access-Control-Allow-Origin: *`, full method and header list) so a browser-based dashboard works without a proxy.

## The State Snapshot

`GET /v1/state` returns this shape, and every `state` event on the WebSocket carries it verbatim — a client has exactly one thing to parse whether it polled or was pushed.

```json
{
  "appMode": "producerControl",
  "network": {
    "isMasterServer": true,
    "isLANConnected": true,
    "isProducerLive": false,
    "hasSyncedWithProducer": false,
    "connectedMasterName": null,
    "lanPort": 13380,
    "relayEnabled": false,
    "relayHost": ""
  },
  "roles": [
    {
      "id": "role-abc123",
      "name": "Operator",
      "personName": null,
      "cue": { "state": "GO", "isActive": false },
      "plotipharRoleId": null,
      "assignedNoteCategories": []
    }
  ],
  "selectedRoleIds": ["role-abc123"],
  "timer": {
    "item": {
      "id": "item-xyz789",
      "title": "Prelude",
      "itemType": "Song",
      "lengthInSeconds": 300,
      "isDurationActual": false,
      "remainingSeconds": 45,
      "isRunning": true,
      "isOvertime": false,
      "servicePlanTitle": "Sunday Morning Service",
      "notes": {},
      "pcoServiceTypeId": null,
      "pcoPlanId": null
    },
    "index": 2,
    "isRunning": true,
    "remainingSeconds": 45,
    "isOvertime": false,
    "formattedRemaining": "0:45",
    "isDurationActualForDisplay": false
  },
  "plan": {
    "title": "Sunday Morning Service",
    "items": [
      {
        "id": "item-xyz789",
        "title": "Prelude",
        "itemType": "Song",
        "lengthInSeconds": 300,
        "isDurationActual": false,
        "remainingSeconds": 45,
        "isRunning": true,
        "isOvertime": false,
        "servicePlanTitle": "Sunday Morning Service",
        "notes": {},
        "pcoServiceTypeId": null,
        "pcoPlanId": null
      }
    ],
    "activeItemIndex": 2,
    "isAtEndOfPlan": false,
    "canLoadNextService": false,
    "pcoServiceTypeId": null,
    "pcoPlanId": null
  },
  "messages": [
    {
      "id": "msg-001",
      "text": "Mic check in 30 seconds",
      "senderRoleId": "role-abc123",
      "targetRoleId": null,
      "isHighPriority": true,
      "timestamp": "2024-01-15T10:30:45Z"
    }
  ],
  "pco": {
    "isConnected": false,
    "userName": null,
    "isLiveSyncEnabled": false,
    "lastError": null,
    "selectedServiceTypeId": null,
    "defaultServiceTypeId": null,
    "planFilter": "all",
    "serviceTypes": [],
    "plans": [],
    "noteCategories": []
  },
  "plotiphar": {
    "pairingState": "idle",
    "pairingCode": null,
    "pairingExpiresAt": null,
    "pairingError": null,
    "assignmentSyncStatus": "notSynced",
    "assignmentSyncEventId": null,
    "assignmentSyncError": null,
    "roles": []
  },
  "settings": {
    "hourFormatThreshold": "over90Minutes",
    "controlAPIPort": 13390,
    "connectedAPIClients": 1
  },
  "waypoints": [
    {
      "id": "waypoint-abc123",
      "name": "Song 2",
      "slug": "song-2",
      "itemId": "item-xyz789",
      "itemTitle": "How Great Thou Art",
      "itemIndex": 4
    },
    {
      "id": "waypoint-def456",
      "name": "Sermon",
      "slug": "sermon",
      "itemId": null,
      "itemTitle": null,
      "itemIndex": null
    }
  ],
  "schedules": {
    "entries": [
      {
        "id": "sched-001",
        "title": "Sunday 10am",
        "startsAt": "2026-10-04T14:00:00Z",
        "goLiveAt": "2026-10-04T13:30:00Z",
        "goLiveOffsetSeconds": 1800,
        "goLiveOffsetMinutes": 30,
        "pcoServiceTypeId": "st-1",
        "pcoPlanId": "plan-1",
        "recurrence": "weekly",
        "isEnabled": true,
        "lastFiredAt": null
      }
    ],
    "nextId": "sched-001"
  }
}
```

**Key pieces:**
- **`appMode`** is one of the app's internal display modes (`producerControl`, `pagerLive`, etc.), expressed as the wire value. These are stable identifiers, not UI labels — `producerControl` is the section the Producer now shows as "Pagers".
- **`notificationsClearedAt`** is the line between "already dealt with" and "somebody should be looking at this". A message newer than it is still notifying; everything at or before it has been acknowledged. `null` means nothing has ever been cleared. This is how a producer takes a message off a lower third without deleting the thread — a separate act from `DELETE /v1/messages`, and the reason both exist.
- **`timer`** is `null` when no plan is loaded or when the loaded plan is nothing but headers — there's genuinely no active item then, and inventing a placeholder would make "is something running?" unanswerable.
- **`roles`**, **`plan.items`**, **`messages`** use the app's own `Codable` models verbatim (`RoleCue`, `PCOTimerItem`, `InterTeamMessage`). An integrator reading this API and someone reading `Server/PROTOCOL.md` see one vocabulary.
- **`formattedRemaining`** is the time string the producer's own screen shows, run through `TimeFormatting.string` so a Stream Deck button and the UI can't disagree about when a countdown reads `1:35:00` versus `95:00`.
- **`isDurationActualForDisplay`** is the Projected/Actual flag being shown — the plan item's own flag unless the live header's transient override applies.
- **`pairingState`** and **`assignmentSyncStatus`** are string names, not enum cases (Plotiphar states have associated values and JSON has no natural representation for those).
- **`waypoints`** is the whole waypoint library plus this week's resolution — `itemId`/`itemTitle`/`itemIndex` are `null` on an entry nothing in the current plan carries, same "not wired up yet" meaning as `timer` being `null`. See [Waypoints](#service-waypoints).
- **`schedules.nextId`** is the id (or `null`) of whichever entry in `schedules.entries` is the next one that will actually fire, so a client can render "next: Sunday 10am, live at 9:30" without reasoning about every entry itself. See [Service Schedules](#service-schedules).

## Routes

Grouped by function. Dates in requests and responses are ISO-8601. Every request body field is optional unless the route description says otherwise (a route that requires a name will reject an empty request or a null name).

### Health & Status

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/health` | GET | Returns `{"service": "13 Years Control API", "version": "1.0.0", "device": "<hostname>", "role": "master\|client"}` so monitoring can verify the API is alive and identify this device. |
| `GET /v1/state` | GET | Full state snapshot (see above). |

### Roles

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/roles` | GET | List all roles. |
| `POST /v1/roles` | POST | Create a role. Body: `{"name": "string"}`. Returns the new role (201). Name is required and cannot be empty. |
| `GET /v1/roles/{id}` | GET | Read one role. |
| `PATCH /v1/roles/{id}` | PATCH | Update a role. Body: `{"name": "string?", "personName": "string?", "plotipharRoleId": "string?", "assignedNoteCategories": ["string"]?, "state": "string?"}`. All fields optional (absent means leave alone). Returns the updated role. Name cannot be empty if present. |
| `DELETE /v1/roles/{id}` | DELETE | Remove a role. Returns the new role list. |
| `POST /v1/roles/{id}/cue` | POST | Fire a cue for one role. Body: `{"state": "string"}`. State must be one of the `CueState` enum values — `OFF`, `STANDBY`, `GO`, uppercase. (`RESET` is *not* one of them; clearing a cue is `OFF`.) Returns the full state snapshot. |
| `GET /v1/selection` | GET | Roles currently selected on the producer's screen (list of role ids). |
| `PUT /v1/selection` | PUT | Set which roles are selected. Body: `{"roleIds": ["string"]}`. All ids must be known roles. Returns the full state snapshot. |

### Cues

| Route | Method | Purpose |
|-------|--------|---------|
| `POST /v1/cues/selected` | POST | Fire the same cue for all currently-selected roles. Body: `{"state": "string"}`. State must be `OFF`, `STANDBY`, or `GO` (uppercase). Returns the full state snapshot. |
| `POST /v1/cues/clear` | POST | Clear all cues (set every role to `OFF`). Returns the full state snapshot. |

### Timer

Timer commands only work when a plan is loaded and an item is active (`timer.item` is not null). Routes return 409 if not.

| Route | Method | Purpose |
|-------|--------|---------|
| `POST /v1/timer/start` | POST | Ensure the countdown is running. Idempotent — sending `start` twice doesn't pause. Returns the full state snapshot. |
| `POST /v1/timer/pause` | POST | Pause the countdown. Idempotent. Returns the full state snapshot. |
| `POST /v1/timer/toggle` | POST | Start if paused, pause if running. Returns the full state snapshot. |
| `POST /v1/timer/reset` | POST | Jump the timer to the item's original duration (reset `remainingSeconds` to `lengthInSeconds`). Returns the full state snapshot. |
| `POST /v1/timer/adjust` | POST | Add or subtract seconds. Body: `{"seconds": number}` (integer, can be negative). Returns the full state snapshot. |
| `POST /v1/timer/remaining` | POST | Set or adjust remaining time. Body: either `{"seconds": number}` (absolute) or `{"input": "string"}` (relative/absolute command text). Input uses the same GrandMA-style grammar the producer types: `"4350"` (absolute seconds), `"+30s"`, `"-5m"`, `"1h30m"`. Parsed by the same parser the app's UI uses so a macro pad and a keyboard agree on meaning. Returns the full state snapshot. |
| `POST /v1/timer/actual-override` | POST | Set whether the active timer displays as Projected or Actual. Body: `{"isActual": boolean}`. This is a transient visual override; the plan item's own `isDurationActual` flag is unchanged. Returns the full state snapshot. |

### Plan

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/plan` | GET | The plan structure, metadata, and current position. |
| `POST /v1/plan/next` | POST | Advance to the next item (or mark end-of-plan if already at the last). Returns the full state snapshot. |
| `POST /v1/plan/previous` | POST | Go back to the previous item. Returns the full state snapshot. |
| `POST /v1/plan/next-service` | POST | Load the next service from Planning Center (202). Only works if a PCO flow is synced. Returns the current state snapshot and marks the operation as in-progress; watch for a later `state` event showing the new plan. |
| `GET /v1/plan/active` | GET | Just the active timer item (shorthand for reading it out of the full state). |
| `POST /v1/plan/active` | POST | Jump to a specific item. Body: `{"itemId": "string"}`. Id must exist. Returns the full state snapshot. |
| `POST /v1/plan/items` | POST | Create and append a plan item. Body: `{"title": "string", "itemType": "string?", "lengthInSeconds": number?, "isDurationActual": boolean?}`. Title is required and cannot be empty. Defaults: itemType="Item", lengthInSeconds=300, isDurationActual=false. Returns the plan section of state (201). |
| `POST /v1/plan/items/{id}` | POST | Update a plan item. Body: `{"title": "string?", "itemType": "string?", "lengthInSeconds": number?, "notes": {string: string}?, "isDurationActual": boolean?}`. All fields optional (absent means leave alone). Returns the updated item. |
| `GET /v1/plan/items/{id}` | GET | Read one item. |
| `DELETE /v1/plan/items/{id}` | DELETE | Remove an item. Returns the plan section of state. |
| `POST /v1/plan/items/{id}/duration-actual` | POST | Toggle whether the item displays as Projected or Actual. Body: `{"isActual": boolean}`. Returns the plan section of state. |
| `POST /v1/plan/items/reorder` | POST | Reorder the items in the plan. Body: `{"itemIds": ["string"]}`. List must contain every current item id exactly once. Returns the plan section of state. |
| `POST /v1/plan/import` | POST | Parse and import a service flow. Body: `{"text": "string", "title": "string?"}`. Text is `Title | Type | Duration` (one per line, duration in seconds). If parsing succeeds, a new plan titled `title` (or auto-generated) is created and imported. Returns the plan section (201). |

### Waypoints

A waypoint is base programming that stays put while the content changes weekly. A Companion button labelled "Song 2" doesn't actually know or care which `PCOTimerItem` that is this week — it fires the waypoint, and the waypoint points at whatever item currently carries it. Re-import Sunday's flow, swap the setlist entirely, and the same button still fires the right thing, because the assignment (which item has the waypoint) is expected to change every week while the waypoint itself (its id, its name) is the one thing meant to survive that. A waypoint is on at most one item at a time — assigning it elsewhere takes it away from wherever it was — specifically so firing it is never ambiguous.

`{ref}` in every route below accepts the waypoint's id, its exact name, or its slug (`Waypoint.matches`, case/punctuation-insensitive — "Song 1", "song 1", and "song-1" all resolve to the same waypoint). The slug is what's actually worth typing into a Companion button: a space in a URL path works fine (this app decodes it before it ever reaches a route), but the slug sidesteps the question, and it's the only spelling that survives being used as a dotted WebSocket `op` — a name containing a `.` can't be, since the socket door splits `op` on `.`.

`POST /v1/waypoints/{ref}/go` is the actual "fire this waypoint" button. It answers 404 versus 409 on purpose, and the difference matters to whoever is debugging a dead button: **404** means the waypoint itself doesn't exist — the ref is wrong, or the waypoint was renamed/deleted. **409** means the waypoint exists but nothing in the current week's plan carries it — the button is fine, the *assignment* was never made (or the import that just ran didn't preserve it). One says "fix the button," the other says "assign the waypoint." A Companion button firing `/go` with no body at all is the common case, not an error — that route accepts a missing/empty body the same as `{}`.

One wrinkle worth knowing: PCO *header* items ("Pre Gathering", "Host Moment") are section dividers and aren't selectable, so a waypoint assigned to a header fires onto the nearest real item in that section instead. That is usually what you want — a waypoint naming a section fires that section's first item — but it does mean the item that ends up active may not be the one the waypoint is assigned to, so don't assert equality between `waypoints[].itemId` and `timer.item.id` after firing.
| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/waypoints` | GET | List the waypoint library, each with this week's resolution (which item, if any, currently carries it). |
| `POST /v1/waypoints` | POST | Add a waypoint to the library. Body: `{"name": "string"}`. Name is required, cannot be empty, and its slug must not collide with an existing waypoint's (409, case/punctuation-insensitive — "Song 1" and "song 1" collide). Returns the new waypoint (201). |
| `GET /v1/waypoints/{ref}` | GET | Read one waypoint. |
| `PATCH /v1/waypoints/{ref}` | PATCH | Rename a waypoint. Body: `{"name": "string"}`. The id never changes, so every existing assignment and every button already pointed at the id keeps working through a rename. Empty name is 400; a new slug colliding with a *different* waypoint is 409 (renaming a waypoint to a different casing of its own name is fine). |
| `DELETE /v1/waypoints/{ref}` | DELETE | Remove a waypoint from the library and strip it from every plan item's assignment. Returns the remaining waypoint list. |
| `POST /v1/waypoints/{ref}/assign` | POST | Assign (or unassign) this waypoint for the week. Body: `{"itemId": "string?"}` — a null or absent `itemId` unassigns. Assigning steals the waypoint away from whatever other item held it, since a waypoint is on at most one item at a time. 404 if the waypoint or the item id doesn't exist. Returns the updated waypoint. |
| `POST /v1/waypoints/{ref}/go` | POST | Fire the waypoint — jump to whatever item currently carries it, identically to tapping that row in Service Flow, **which includes starting its countdown**. Body: `{"startTimer": boolean?}`, optional and normally absent; absent means `true`. Send `{"startTimer": false}` to jump without running the clock, for pre-rolling to a cue ahead of time. Firing the same waypoint twice never pauses a running show. 404 if the waypoint doesn't exist; **409** if it exists but nothing in this week's plan carries it (see above). Returns the full state snapshot. |
| `POST /v1/plan/items/{id}/waypoints` | POST | Replace one plan item's whole waypoint list in one call (the item editor's waypoint picker). Body: `{"waypoints": ["string"]}`, each entry resolved by id, slug, or name. A full list rather than add/remove ops, so resending the same state is idempotent. Any entry that doesn't resolve to a real waypoint is a 404 naming which one; each kept waypoint is stolen away from whatever other item held it, same as `/assign`. Returns the plan section of state. |

### Service Schedules

A schedule is a producer's standing "this service goes live at this time" plan — pick a lead time once (e.g. "30 minutes before 10am") instead of remembering to press Go Live by hand every week. `goLiveOffsetMinutes`/`goLiveOffsetSeconds` is that lead time: the app switches into the live producer view at `startsAt` minus the offset, not at `startsAt` itself, so there's room to get the room ready before the service actually starts.

Firing is checked every few seconds by the producer app itself — never by a client of this API. A client can ask for it early with `POST /v1/schedules/{id}/go-live`, but nothing about this feature runs client-side; a pager or a browser dashboard watching the socket only ever *observes* a schedule firing, through the `state` event that follows. A **late-fire grace window** (one hour past `startsAt`) covers a producer who opens the app after the service's own start time — the schedule still catches up and goes live — without reaching so far past start that firing would surprise rather than help; past that window it stays down rather than springing a stale schedule out of context.

What firing leaves behind depends on `recurrence`. A **`once`** schedule stamps `lastFiredAt` and disables itself — it won't fire again, but the record of what was scheduled and when stays visible rather than disappearing. A **`weekly`** schedule rolls `startsAt` forward to next week's occurrence (by calendar day, so a service that starts at 10:00 keeps starting at 10:00 across a daylight-saving change, not 9:00 or 11:00) and clears `lastFiredAt`, staying enabled and armed for next week.

A schedule without `pcoServiceTypeId`/`pcoPlanId` only switches the app into the live producer view — it does not load or change the plan. That's a real, supported configuration: a producer who loads Sunday's plan by hand but still wants the mode switch itself automated sets a schedule with no PCO ids.

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/schedules` | GET | List the schedule library. Same shape as the `schedules` key in the state snapshot: `{"entries": [...], "nextId": "string?"}`. |
| `POST /v1/schedules` | POST | Add a schedule. Body: `{"title": "string", "startsAt": "ISO-8601", "goLiveOffsetMinutes": number?, "goLiveOffsetSeconds": number?, "pcoServiceTypeId": "string?", "pcoPlanId": "string?", "recurrence": "once\|weekly", "isEnabled": boolean?}`. `goLiveOffsetMinutes` wins if both offsets are sent; default lead time is 30 minutes, default recurrence `once`. Title is required and cannot be empty; the lead time cannot be negative (that would mean "go live after the service starts," which isn't a thing this feature does); an unrecognised `recurrence` is 400. Returns the new entry, `goLiveAt` included (201). |
| `GET /v1/schedules/{id}` | GET | Read one schedule. |
| `PATCH /v1/schedules/{id}` | PATCH | Update a schedule. Same body shape as create, all fields optional (absent means leave alone). Changing `startsAt` or either offset field clears `lastFiredAt` — the firing window just moved, so whatever fired the old one has nothing to say about the new one. |
| `DELETE /v1/schedules/{id}` | DELETE | Remove a schedule. Returns the remaining list. |
| `POST /v1/schedules/{id}/go-live` | POST | Fire a schedule right now, same as if its lead time had just arrived (202 — the PCO fetch, if any, happens in the background; watch the socket for the resulting `state`). 404 if the id doesn't exist. |

### Planning Center Online

These routes start background operations; most return 202. Poll `/v1/pco` or watch the WebSocket `state` events for progress.

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/pco` | GET | The PCO connection status, selected service type, available plans, available note categories. |
| `POST /v1/pco/sign-in` | POST | Open a browser to start PCO OAuth (202). The sign-in completes on the device; there is no way to complete an OAuth grant through this endpoint. Watch the socket for `pco.isConnected` to change. |
| `POST /v1/pco/sign-out` | POST | Disconnect from PCO. Returns the PCO section of state. |
| `GET /v1/pco/service-types` | GET | List available service types (calendar segments in PCO, e.g., Sunday Morning, Wednesday Evening). Returns an array of `{"id": "string", "name": "string"}`. |
| `POST /v1/pco/service-types/refresh` | POST | Fetch the latest service types from PCO (202). Watch the socket for `pco.serviceTypes` to update. |
| `POST /v1/pco/service-type` | POST | Select a service type to filter plans. Body: `{"id": "string"}`. Returns 202 (the selection takes effect immediately but plan lists are refreshed asynchronously). |
| `POST /v1/pco/default-service-type` | POST | Remember this service type for next time. Body: `{"id": "string?"}` (null clears). Returns the PCO section of state. |
| `GET /v1/pco/plans` | GET | List available plans for the selected service type. Returns an array of `{"id": "string", "title": "string", "dates": "string?"}`. |
| `POST /v1/pco/plans/refresh` | POST | Fetch the latest plans from PCO (202). Requires a service type to be selected (409 if not). Watch the socket for `pco.plans` to update. |
| `POST /v1/pco/plan-filter` | POST | Set which plans to show (e.g., upcoming, past, all). Body: `{"filter": "string"}`. Returns 202. |
| `POST /v1/pco/sync` | POST | Fetch a specific plan and populate the local plan with its items (202). Body: `{"serviceTypeId": "string", "planId": "string"}`. Returns the current state and fetches in the background; watch the socket for `plan` to update. |
| `POST /v1/pco/live-sync` | POST | Enable or disable PCO Live synchronization. Body: `{"enabled": boolean}`. Returns 202 (the toggle takes effect immediately but initial sync happens asynchronously). |

### Plotiphar

Plotiphar is a companion app for lighting/scenic control. These routes manage pairing and assignment syncing.

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/plotiphar` | GET | Pairing status, available roles, and assignment sync status. |
| `POST /v1/plotiphar/pair/start` | POST | Initiate pairing with Plotiphar (202). A pairing code is issued by plotiphar.com and appears in `plotiphar.pairingCode` shortly; poll or watch the socket. |
| `POST /v1/plotiphar/pair/cancel` | POST | Cancel an in-progress pairing. Returns the Plotiphar section of state. |
| `POST /v1/plotiphar/assignments/sync` | POST | Fetch role assignments from Plotiphar (202). Watch the socket for `plotiphar.assignmentSyncStatus` to change. |
| `POST /v1/plotiphar/disconnect` | POST | Clear the Plotiphar pairing. Returns the Plotiphar section of state. |

### Network

| Route | Method | Purpose |
|-------|--------|---------|
| `POST /v1/network/ping` | POST | Send a UDP ping to a device on the LAN to wake it or signal the app to go live. Body: `{"ip": "string"}` (required, non-empty). Returns 202 (fire-and-forget; UDP has no acknowledgement). Returns 503 if this device cannot determine its own LAN address. |
| `POST /v1/network/forget-producer` | POST | Clear the assigned producer (client mode only). Returns the full state snapshot. |
| `POST /v1/network/master` | POST | Switch between master and client mode. Body: `{"isMaster": boolean}`. Returns the full state snapshot. |

### App Navigation

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/ui/mode` | GET | The current app mode (display screen). Returns `{"mode": "string"}`. |
| `POST /v1/ui/mode` | POST | Switch the app's display mode. Body: `{"mode": "string"}`. Mode must be one of the app's actual `AppMode` cases (e.g., `producerControl`, `pagerLive`). Accepts either uppercase wire form (PRODUCER_CONTROL) or camelCase (producerControl). Returns `{"mode": "string"}`. |

### Settings

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/settings` | GET | App settings. |
| `PATCH /v1/settings` | PATCH | Update settings. Body: `{"hourFormatThreshold": "string?"}`. Valid values are the `HourFormatThreshold` raw values — `over60Minutes`, `over90Minutes`, `never` — and anything else is a 400 listing them. (`never` means always `MM:SS`, however long the duration runs.) Returns the settings section of state. |

### Messages

| Route | Method | Purpose |
|-------|--------|---------|
| `GET /v1/messages` | GET | Recent messages (up to the app's history limit). |
| `POST /v1/messages` | POST | Send a message to one or all roles. Body: `{"text": "string", "targetRoleId": "string?", "senderRoleId": "string?", "isHighPriority": boolean?}`. Text is required and cannot be empty. Returns the full message history (201). |
| `DELETE /v1/messages` | DELETE | Clear the message history. Returns the empty list. |
| `POST /v1/messages/dismiss` | POST, DELETE | Clear the *standing notification* without deleting anything. Every message stays in the thread; the banners and lower thirds showing one come down. Sets `notificationsClearedAt` and returns the state snapshot. |

### Relay (Plotiphar Off-LAN Proxy)

| Route | Method | Purpose |
|-------|--------|---------|
| `PUT /v1/relay` | PUT | Configure the off-LAN relay. Body: `{"enabled": boolean?, "host": "string?"}`. Both fields optional. Setting `host` changes the relay address; setting `enabled: true` without an existing pairing returns 409. `proxyToken` is deliberately absent in both directions — it's a Keychain-held session credential, and handing it out over an unauthenticated LAN endpoint would make the relay's own auth boundary meaningless. Pairing happens on the device via `POST /v1/plotiphar/pair/start`. Returns the full state snapshot. |

## The WebSocket

**Endpoint:** `ws://<device>:13390/v1/socket`

A WebSocket that stays open for the life of the service, giving the producer a second door onto the same router. Useful for receiving unsolicited updates (timer ticking, messages arriving) and for sending commands without creating a new HTTP connection for each one.

### Receiving (Server to Client)

On connect, the server immediately sends a `hello` event carrying the full state snapshot, so a client never needs a REST call just to prime itself:

```json
{
  "event": "hello",
  "data": { ... full ControlAPIState ... }
}
```

Then, as the show runs:

```json
{
  "event": "state",
  "data": { ... full ControlAPIState ... }
}
```

`state` events are coalesced; they fire roughly 1 Hz while a timer is counting down, and less frequently when the show is idle. A client that skipped the `hello` event and receives only `state` events will be kept in sync.

```json
{
  "event": "message",
  "data": { ... InterTeamMessage ... }
}
```

When a message is sent, each connected socket receives a `message` event (in addition to the next `state` event that includes the updated message list).

### Sending (Client to Server)

The socket accepts the same routes as REST, but spelled as dotted paths instead of HTTP paths. The `op` field replaces the HTTP method and path:

```json
{
  "id": "abc-123",
  "op": "cues.selected",
  "body": { "state": "GO" }
}
```

The `id` is optional; if supplied, it appears in the reply so a client can correlate request and response. The `op` is the dotted form of the path: `/v1/plan/next` becomes `plan.next`, `/v1/roles/{id}/cue` becomes `roles.{id}.cue`. The `body` is that route's JSON body verbatim.

The server replies:

```json
{
  "id": "abc-123",
  "status": 200,
  "data": { ... full ControlAPIState ... }
}
```

Or, on error:

```json
{
  "id": "abc-123",
  "status": 400,
  "error": "Unknown cue state",
  "data": { "error": "Unknown cue state", "detail": "OFF, STANDBY, GO" }
}
```

The `status` is the same HTTP status the same route would return over REST, and `data` is that route's response body verbatim — which for an error is the same `{"error", "detail"}` shape REST returns. `error` is lifted out to the top level so a client can show something useful without reaching into `data`.

## The Web Pager

The Producer serves a pager screen to any browser off this same listener: **`http://<device>:13390/pager`** (`/` redirects there, so the bare address works too). It is the app's fourth pager platform, after iPhone/iPad, Apple Watch and the ESP32 panel, and it exists for the screens a venue already has and can't install an app on — a laptop at the sound desk, an OBS browser source, a ribbon display over the stage, a volunteer's tablet twenty minutes before a service.

It is a client of this API like any other control surface: one self-contained page, then the same `hello`/`state` push over `/v1/socket`. It also *asks* — a `GET /v1/state` whenever two seconds pass with nothing arriving, the same thing the Watch pager does at 1 Hz — because a show sitting on a paused timer changes nothing for minutes at a time, and silence from a push-only feed is indistinguishable from a dead link. That heartbeat is also the whole transport if the socket can't be established. Nothing about it is a second protocol.

The connection line reads `Live — <device>`, the producer's own device name from `GET /v1/health`.

**Reads the show, writes only messages.** It renders cues, the running item and countdown, assigned note panels and whatever message is currently standing. It cannot fire a cue or touch the plan.

Its Messages button opens the same merged, tagged timeline `PagerChatView` gives the phone — Everyone broadcasts plus this role's own thread with the Producer, oldest first — with a composer at the bottom. Sending posts to `POST /v1/messages` on that pager's own thread (`targetRoleId` and `senderRoleId` both the selected role, exactly as `PagerChatView` addresses a reply); the chat header's Clear History calls `DELETE /v1/messages` behind a two-press confirmation.

The banner on the home page *is* the standing notification, so clicking it clears it (`POST /v1/messages/dismiss`) — off every web pager and every lower third at once, thread untouched. The Producer app's Messages section has the same control as a Clear Notification button.

| Parameter | Values | Meaning |
| --- | --- | --- |
| `role` | a role id or name, case-insensitive | Which role's cue to show — `?role=Host` or `?role=Front%20of%20House`. Takes precedence over whatever that browser last had selected, every load, so a bookmark or an OBS source URL is stable. Falls back to the first role if it matches nothing. |
| `layout` | `auto` (default), `standard`, `lowerthird` | `auto` picks per viewport. |

**Two layouts.** The standard one is the same screen every other pager shows — full-bleed cue color, the state word, the running item and its countdown, note panels, the latest message. A short, wide viewport (height ≤ 400px, or an aspect ratio of 3:1 or wider) switches to a single lower-third line instead:

```
  [ 4:28:01 PM        Welcome & Announcements        06:32 ]
```

The element name sits in the same dark panel the standard layout's item card uses, and the countdown carries the same PROJECTED/ACTUAL waypoint. A message for that pager's role — one arriving live, or one already standing when the page loads — takes over the clock and the element name, in the same yellow card the standard layout shows it in, scaled to fit, while the countdown stays put, since it's the one field nobody watching can reconstruct for themselves. It stays up until the notification is cleared (from a web pager or the Producer app), which is deliberate: nobody can tap a lower third, and the producer is the one who knows whether the host has read it.

Both are resolution-independent rather than breakpoint-driven: every size is a multiple of one viewport-derived step, so the same URL is a phone pager, a 4K lobby display and a 1920x260 browser source. The element name shrinks to fit the room the clock and the countdown leave it before it truncates.

**Fonts** are served from the app bundle (`/pager/fonts/Inter-*.ttf`, whitelisted — not a static file server), so a machine that has never heard of Inter still renders the same pager as the phone does.

## What This API Deliberately Does NOT Do

Following the design philosophy in `Server/PROTOCOL.md`:

- **Does not expose or accept `proxyToken`.** It's a Keychain-held credential; pairing happens on the device via `POST /v1/plotiphar/pair/start`, not through the API. An integrator should never see it.
- **Cannot complete a Planning Center OAuth sign-in.** The API can only start the flow on the device, opening a browser. OAuth completion is a device-resident operation, hence 202 and the need to watch the socket.
- **Holds no state of its own and caches nothing.** The engine is the single source of truth. A state snapshot is built fresh on every call (it's cheap next to the JSON encoding that always follows). If caching lived in the API, it would be one more thing that can go stale mid-service.
- **Does not run when the app is backgrounded on iPad.** iOS suspends the app and the listener with it. The API is useless if the app isn't in the foreground on that device — a production constraint, not a design choice, but worth knowing.
- **Is not reachable off-LAN.** The relay (Plotiphar proxy) is deliberately an opaque auth-and-proxy for cue packets, not an API gateway. Off-LAN control comes through the relay's own message format, not through this API.

## Examples

### Get the Current State

```bash
curl http://producer.local:13390/v1/state | jq
```

### Fire a GO Cue for All Selected Roles

```bash
curl -X POST http://producer.local:13390/v1/cues/selected \
  -H 'Content-Type: application/json' \
  -d '{"state": "GO"}'
```

### Adjust the Timer (Add 30 Seconds)

```bash
curl -X POST http://producer.local:13390/v1/timer/adjust \
  -H 'Content-Type: application/json' \
  -d '{"seconds": 30}'
```

### Set Timer to Absolute Time

```bash
curl -X POST http://producer.local:13390/v1/timer/remaining \
  -H 'Content-Type: application/json' \
  -d '{"input": "1h30m"}'
```

### Advance the Plan

```bash
curl -X POST http://producer.local:13390/v1/plan/next
```

### Send a Message

```bash
curl -X POST http://producer.local:13390/v1/messages \
  -H 'Content-Type: application/json' \
  -d '{"text": "30 seconds to go", "isHighPriority": true}'
```

### Fire a Service Waypoint (a Companion Button Labelled "Song 2")

```bash
curl -X POST http://producer.local:13390/v1/waypoints/song-2/go
```

No body required — this is exactly what a Companion button press looks like on the wire, and it starts the item's countdown just as tapping the row would. Add `-d '{"startTimer": false}'` to jump to the item and leave the clock paused instead.

### Assign a Waypoint to This Week's Item

```bash
curl -X POST http://producer.local:13390/v1/waypoints/song-2/assign \
  -H 'Content-Type: application/json' \
  -d '{"itemId": "item-xyz789"}'
```

Do this once per week after importing the new flow, and every button already pointed at `song-2` keeps working unchanged.

### Create a Schedule That Goes Live 30 Minutes Early

```bash
curl -X POST http://producer.local:13390/v1/schedules \
  -H 'Content-Type: application/json' \
  -d '{"title": "Sunday 10am", "startsAt": "2026-10-04T14:00:00Z", "goLiveOffsetMinutes": 30, "recurrence": "weekly"}'
```

The app switches into the live producer view at 9:30 UTC — 30 minutes before the 10:00 UTC `startsAt` — and, being `weekly`, rolls itself forward to the next Sunday once it fires.

### Connect to the WebSocket and Send a Command

```bash
websocat ws://producer.local:13390/v1/socket
```

Once connected, you'll receive the `hello` event. Then send a command:

```json
{"id":"1","op":"plan.next"}
```

The server replies with the new state.
