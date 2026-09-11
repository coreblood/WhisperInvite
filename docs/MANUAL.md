# WhisperInvite — User Manual (v1.3.0)

WhisperInvite does two things:

1. **Whisper-invite** — when someone whispers you *exactly* the keyword
   (default: `inv`), they are automatically invited to your group. The
   keyword inside a longer sentence never triggers an invite. By default
   only players on your **greenlight list** can trigger this; strangers are
   silently ignored (`/wi scope everyone` opens it up for pug hosting).
2. **Auto-accept** — when a player you have *greenlighted* invites you, the
   invite is accepted automatically (even while you are AFK), and the invite
   popup is cleared.

Client: WotLK 3.3.5a (Interface 30300).

## Installation

Copy the `WhisperInvite` folder into `Interface\AddOns\` and restart the
client (or `/reload` if it was already installed).

## The minimap button

A round button sits on your minimap edge. The icon is **green** while
whisper-invite is listening and **red** while it is off.

- **Left-click** — toggle whisper-invite on/off.
- **Right-click** — open the options panel.
- **Shift + left-click and drag** — move the button **anywhere** around or
  on the minimap; it stays exactly where you drop it. This works with any
  minimap addon, shape, or scale. (Moving the button never toggles the
  addon.)

## Options panel

Open it via right-click on the minimap button, `/wi options`, or
Interface → AddOns → WhisperInvite. It contains:

- **Enable whisper-invite** — the master switch for keyword invites.
- **Whisper a confirmation back** — whether the invited player receives
  "You have been automatically invited."
- **Keyword** — type a new keyword and press Enter. The whisper must be
  exactly this word; matching is case-insensitive and surrounding spaces
  are ignored.
- **Only greenlighted players can trigger the keyword** — checked (default):
  whispers from players not on your greenlight list are silently ignored.
  Uncheck to let anyone trigger the keyword (open/pug mode).
- **Auto-accept invites from greenlighted players** — master switch for
  auto-accept.
- **Player + Greenlight button** — add a name to the greenlight list.
- **Remove selected** — click a name in the list, then this button, to remove it.

## Slash commands

| Command | Effect |
|---|---|
| `/wi` or `/wi toggle` | Toggle whisper-invite |
| `/wi on` / `/wi off` | Set whisper-invite explicitly |
| `/wi keyword <word>` | Set the invite keyword |
| `/wi scope greenlist\|everyone` | Who may trigger the keyword (default: greenlist) |
| `/wi allow <name>` | Greenlight a player (auto-accept their invites) |
| `/wi disallow <name>` | Remove a player from the greenlight list |
| `/wi list` | Print the greenlight list |
| `/wi accept` | Toggle auto-accept |
| `/wi reply` | Toggle the confirmation whisper |
| `/wi status` | Print a one-line status summary |
| `/wi options` | Open the options panel |

`/whisperinvite` works everywhere `/wi` does.

## Behaviour notes

- Keyword matching is always exact: case-insensitive, spaces trimmed, the
  whisper must be the keyword and nothing else. "inv please" and "my
  inventory is full" never trigger an invite.
- The greenlight list serves both features: in the default greenlist scope
  it controls who may trigger the invite keyword, and it always controls
  whose invites are auto-accepted.
- If you are in a group but not the leader (or raid assist), the addon tells
  you locally and does not attempt the invite. If the group is full, the
  whisperer is told so (when the confirmation whisper is on).
- Auto-accept fires on the invite event itself, so it works while AFK. It
  cannot work while you are at a loading screen or logged out.
- Greenlight names are stored per account (saved variables), matched
  case-insensitively, and realm suffixes are stripped.

## Settings storage

All settings live in `WhisperInviteDB` (account-wide SavedVariables). New
versions merge missing defaults into an existing database automatically.
