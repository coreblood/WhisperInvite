# WhisperInvite — Changelog

## v1.3.0 (2026-09-08)

### Changed
- **Keyword matching is now always exact** — the whisper must be exactly the
  keyword (case-insensitive, spaces trimmed). The "contains" mode (keyword
  anywhere inside the whisper) is removed entirely as accident-prone: it
  could invite people whose whisper merely contained the keyword by chance.
  `/wi mode` is gone; existing saved settings with contains mode simply
  behave as exact from now on.
- **Options panel reordered**: the Keyword field now sits directly under the
  whisper-invite checkboxes (with a one-line hint stating the exact-match
  rule), and the greenlist-scope checkbox follows it. The former
  "Exact match only" checkbox is removed along with the mode.

## v1.2.1 (2026-09-08)

### Fixed
- Options panel: the "Exact match only" checkbox label ran past the panel
  edge and was clipped. The label is now short, and its explanation
  ("Unchecked: the keyword anywhere inside the whisper triggers the
  invite.") sits on its own grey line directly beneath the checkbox, with
  the controls below re-anchored.

## v1.2.0 (2026-09-07)

### Added
- **Invite scope** (`/wi scope greenlist|everyone`, also in the options
  panel): controls who may trigger the invite keyword. **Default is
  greenlist** — only players on your greenlight list are invited when they
  whisper the keyword; everyone else is silently ignored (no reply whisper,
  no spam). "Everyone" restores the open behaviour for hosting pugs.
  The minimap tooltip and `/wi status` now show the active scope.

### Notes
- This closes the "anyone whispering inv gets invited" hazard: the shipped
  default keyword (`inv`) is extremely common, and the enabled state
  persists across sessions by design, so an open listener could fire on
  strangers. With greenlist scope as the default, the listener is private
  unless explicitly opened.

## v1.1.3 (2026-09-07)

### Fixed
- **The gold ring now actually circles the icon.** The border, icon, and
  background textures inside the button were misaligned (ring drawn
  up-left, icon poking out bottom-right). The button now uses the canonical
  Blizzard/LibDBIcon layout — border at TOPLEFT (0,0) of the 31px button,
  17px icon inset at (7,-6), 20px background at (7,-5) — which centers the
  icon inside the visible ring. The icon's square edges are also trimmed
  (`SetTexCoord 0.05–0.95`) so corners don't stick out of the round border,
  and the button gained the standard hover highlight.

## v1.1.2 (2026-09-07)

### Changed
- **Minimap button placement is now free-form.** Shift+drag places the
  button at the exact spot you release it (stored as x/y offsets from the
  minimap center) instead of snapping it to a computed circle. Radius
  formulas cannot match every custom UI — minimap addons that *scale* the
  map (rather than resize it) report the stock 140px width, which made both
  the v1.0 fixed radius and the v1.1.1 size-based radius land off the
  visible ring. Position is loosely clamped so the button can sit on any
  ring or corner but cannot be dragged off-screen and lost.
- Existing installs migrate automatically: the old stored angle seeds the
  initial position once, then the button is yours to place.

## v1.1.1 (2026-09-06)

### Fixed
- **Minimap button landed inside the circle on scaled/resized minimaps.**
  The anchor radius was hardcoded to 80 (correct only for the default 140px
  minimap). It is now computed from the minimap's actual size
  (`width/2 + 10`), so the button sits on the border ring at any minimap
  size. The button also re-anchors on `PLAYER_ENTERING_WORLD`, in case a
  minimap addon resizes the minimap after this addon loads.

## v1.1 (2026-09-06)

### Fixed
- **Keyword matching**: now case-insensitive *plain-text* matching with a
  configurable mode. Default is **exact** (whisper must equal the keyword);
  the old anywhere-in-message behaviour is available as **contains**, now
  immune to Lua pattern characters in the keyword.
- **Shift-drag no longer toggles the addon**: releasing the mouse after
  moving the minimap button used to fire the click handler and flip the
  enabled state; the click is now suppressed after a drag.
- **Saved-variable defaults merge**: loading an older/partial
  `WhisperInviteDB` no longer risks nil-concatenation errors; missing keys
  are filled in from defaults (recursively, including the greenlight list).
- **Minimap drag `OnUpdate`** is now attached only while dragging instead of
  running every frame permanently.
- **`/wi on` / `/wi off`** are real commands now instead of silently becoming
  the keyword; keyword changes require the explicit `/wi keyword <word>`.
- **Scoping/global pollution**: `UpdateMinimapButtonLook` and
  `UpdateMinimapButtonPosition` (and all new helpers) are file-locals,
  forward-declared above every reader.
- Minimap tooltip refreshes live while open when the state is toggled.
- Removed dead `WI.defaultKeyword`.
- Invite attempts are guarded: no attempt when you lack invite rights
  (party non-leader / raid non-assist) or when the group is full, with local
  feedback (and a "group is full" whisper to the requester when auto-reply
  is on).

### Added
- **Options panel** (Interface → AddOns → WhisperInvite; also right-click on
  the minimap button or `/wi options`): toggles for whisper-invite,
  confirmation whisper, exact/contains match mode and auto-accept; keyword
  editbox; greenlight-list editor with scrollable list, add and
  remove-selected. Built lazily after `ADDON_LOADED`.
- **Auto-accept from greenlighted players**: invites from names on your
  greenlight list are accepted automatically and the invite popup is
  cleared — works while AFK. Managed via the options panel or
  `/wi allow <name>` / `/wi disallow <name>` / `/wi list`, toggled with
  `/wi accept`.
- New slash commands: `on`, `off`, `keyword`, `mode`, `allow`, `disallow`,
  `list`, `accept`, `reply`, `status`, `options`, plus `/whisperinvite`
  as a long alias. Unknown input prints help instead of doing something
  surprising.
- First MANUAL.md and CHANGELOG.md (standing suite rule: both are updated
  with every release).

## v1.0

- Initial version: keyword whisper-invite (substring match), movable
  minimap button, `/wi` slash command.
