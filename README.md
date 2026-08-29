# !CleanStart

A World of Warcraft addon that captures all messages during login and provides a GUI to review and manage them.

## Features

- **Message Capture**: Captures all chat messages during a configurable login window
- **GUI Review Window**: Press `/cs` to open a window showing all captured messages
- **Smart Categorization**:
  - **Addon messages** (no ID) - Blocked during the login window; Allow / Block / Custom buttons to change that
  - **System messages** (with ID) - Allowed by default; Allow / Block / Custom buttons to filter by text
- **Text-Based Blocking**: When you block a message, only that exact text is blocked (not all messages with the same ID)
- **Persistent Choices**: Your Block decisions are saved account-wide
- **Whitelist System**: Protect important messages from being filtered - by text pattern, or by addon (nothing a whitelisted addon prints is blocked)
- **Debug Mode**: See detailed information about message processing
- **Combat-Safe Reload**: Safely handles `/reload` during combat - delays cleanup until combat ends
- **Instance-Safe Reload**: If you `/reload` while already inside a dungeon or raid, the capture window is skipped entirely instead of briefly running against live chat
- **Lightweight**: Minimal impact on game performance

## Installation

1. Download the addon
2. Extract the `!CleanStart` folder to your WoW `Interface/addons/` directory:
   - **Retail**: `World of Warcraft/_retail_/Interface/addons/`
3. Restart World of Warcraft or reload your UI (`/reload`)

## How It Works

### Login Window Capture

When you log in, the addon captures ALL chat messages during a short window (default 3 seconds). Addon messages are blocked during this window, while system messages are allowed through.

If `/reload` is used while you're already inside a dungeon or raid, there's no login spam to catch, so CleanStart detects this and skips the capture window entirely rather than running it against live instance chat.

### Message Types

The addon distinguishes between two message types:

1. **Addon Messages** (no message ID)
   - Output from an addon's `print()` calls during login
   - **Blocked by default during the login window**
   - Displayed in the GUI with a red background
   - Show **Allow / Block / Custom** buttons, same as system messages - here **Allow** whitelists the exact line so it comes through next login

2. **System Messages** (with message ID)
   - These include player chat and Blizzard system messages
   - **Allowed by default** - but you can choose to block specific message text
   - Displayed in the GUI with a green background
   - Show **Allow / Block / Custom** buttons

### Using the GUI

Type `/cs` to open the captured messages window:

- Messages are listed in chronological order
- Each message shows a type indicator (`[ADDON]` / `[SYSTEM]`), the message ID for system messages, the message text, and action buttons
- The row status shows what will happen next login: `Blocked by default`, `ALLOWED (whitelist)`, or `BLOCKED (filter)`

### Actions

Both message types have the same three buttons:

|   Button   |   System message   |   Addon message   |
|------------|--------------------|-------------------|
| **Allow** | Removes any block filter matching this message | Adds the exact text to the whitelist; removes any block filter matching it |
| **Block** | Blocks the exact message text | Blocks the exact message text; removes an exact whitelist entry for it |
| **Custom** | Dialog to create a custom **block** filter (or block by ID) | Dialog to create a contains / starts-with rule - **allow** by default, or tick *"Block instead of allow"* |

### Custom Filter Dialog

When you click **Custom**, a dialog opens where you can:
- See the full message text (multi-line, scrollable)
- Edit the text to specify what to match
- Add prefix: `^` for starts-with match, `=` for exact match, or no prefix for contains match
- For a system message: tick *"Block by Message ID"* to block every message with that ID
- For an addon message: tick *"Block instead of allow"* to make the rule a block instead of a whitelist entry

**Pattern types** (used by both the block-filter list and the text whitelist):
- `=text` - Exact match (what the "Block" / "Allow" buttons create)
- `^text` - Starts-with match
- `text` - Contains match

## Commands

Use `/cleanstart` or `/cs` to interact with the addon.

| Command | Description |
|---------|-------------|
| `/cs` | Toggle the captured messages window |
| `/cs on\|off` | Enable/disable filtering |
| `/cs status` | Show current status |
| `/cs window <secs>` | Set capture window duration (default: 3s) |
| `/cs list` | List all custom filters |
| `/cs add <text>` | Add filter manually (^starts, =exact) |
| `/cs remove <#>` | Remove a filter by number |
| `/cs clearfilters` | Clear all filters |
| `/cs whitelist add \| remove \| list <text>` | Manage the text whitelist |
| `/cs whitelist addon add \| remove \| list <name>` | Manage the addon whitelist |
| `/cs debug` | Toggle debug output |

## Filter Priority

Messages are processed in this order:

1. **CleanStart's own messages** - Always allowed
2. **Text whitelist** - If matched, message is allowed (wins over everything below)
3. **Custom text filters / blocked IDs** - If matched, message is blocked (an explicit block; not waived by the addon whitelist)
4. **Addon messages** (no ID) - Blocked during the login window by default
5. **Addon whitelist** - Waives the default block from step 4 for messages from a whitelisted addon
6. **System messages** - Allowed

## Custom Text Filters

The **Block** button on a message creates a `=exact` filter; the **Custom** button opens a dialog to build a `^starts-with` or `contains` filter. You can list them with `/cs list`, remove with `/cs remove <#>`, or add them by hand:
```
/cs add DBM                    - Contains "DBM" anywhere
/cs add ^Remember              - Starts with "Remember"
/cs add =Some exact line       - Matches that line exactly
```

## Whitelist

### Text whitelist

Ensure specific messages are never blocked. Matching is **case-insensitive** and
uses the same prefix syntax as block filters - `=exact`, `^starts-with`, or plain
`contains`:
```
/cs whitelist add MyAddon
/cs whitelist add [Raid]
/cs whitelist add ^Loaded:
```
The **Allow** button on a captured message adds a `=exact` entry here. A text
whitelist entry beats every block filter, so keep patterns narrow; to allow an
addon broadly but still block a few of its lines, use the addon whitelist below
instead.

### Addon whitelist

Exempt an entire addon so nothing it prints during the login window is blocked.
Use the addon's **folder name** (as it appears under `Interface/AddOns/`):
```
/cs whitelist addon add EllesmereUI
/cs whitelist addon list
/cs whitelist addon remove EllesmereUI
```
When a message is about to be blocked, CleanStart checks the call stack for a
whitelisted addon's folder. This catches direct `AddMessage` calls, AceConsole
`:Print`, and `print()` wrappers. It won't catch a message pushed from a bare
library callback with no trace of the addon on the stack - add a text whitelist
entry for those. The check only runs when something would otherwise be blocked
*and* the addon whitelist is non-empty, so it has no cost if you don't use it.

## Configuration

Settings are saved per-account in `SavedVariables` and persist between sessions:

- `enabled` - Master toggle for all filtering
- `debug` - Show debug messages with message IDs
- `blockWindow` - Duration of capture window in seconds
- `customFilters` - List of custom text filters (includes blocked message texts)
- `whitelist` - List of whitelisted text patterns
- `addonWhitelist` - List of addon folder names whose messages are never blocked

## Examples

### Check Current Status
```
/cs status
```
Output:
```
CleanStart vx.y.z:
  Filtering    : On
  Debug        : Off
  Capture window : 3s
  Custom filters : 0
  Whitelist entries : 0
  Addon whitelist : 0
  Captured messages : 42
```

### Extend Capture Window
```
/cs window 5
```
This will capture messages for 5 seconds after login.

### Block a Specific Message
1. Open the GUI with `/cs`
2. Find the message in the list
3. Click the **Block** button

The exact text of that message will be added to your custom filters.

## Compatibility

- Only `DEFAULT_CHAT_FRAME` has its `AddMessage` field-replaced (plus the global `print`). Field-replacing a chat frame's `AddMessage` leaves a session-long taint flag on it even after the original is restored, so CleanStart touches as few frames as possible. Addon output routed to a non-default chat tab during the login window is not intercepted.
- If another addon's login messages are getting blocked and you want them kept, add it with `/cs whitelist addon add <name>`. (This stops CleanStart from *blocking* that addon - it does not remove the taint flag on `DEFAULT_CHAT_FRAME`, which nothing can clear once set.)
- **Chat-skinning addons (EllesmereUI, ElvUI, Prat, ...):** these reformat every chat line and push it through `AddMessage` themselves, usually without the numeric message ID CleanStart uses to tell real chat from addon output. During the login window your own chat can be misread as addon spam - add the skin with `/cs whitelist addon add <name>` if that happens. When the window closes, CleanStart restores its hook **only if nothing replaced it in the meantime**, so it will not clobber a chat skin that hooked `AddMessage` after it.

## License

This addon is provided as-is for personal use in World of Warcraft.
