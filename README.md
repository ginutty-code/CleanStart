# !CleanStart

A World of Warcraft addon that captures all messages during login and provides a GUI to review and manage them.

## Features

- **Message Capture**: Captures all chat messages during a configurable login window
- **GUI Review Window**: Press `/cs` to open a window showing all captured messages
- **Smart Categorization**: 
  - **Addon messages** (no ID) - Blocked during login window, displayed for information only
  - **System messages** (with ID) - User can choose to Allow or Block by message text
- **Text-Based Blocking**: When you block a message, only that exact text is blocked (not all messages with the same ID)
- **Persistent Choices**: Your Block decisions are saved account-wide
- **Whitelist System**: Protect important messages from being filtered
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

When you log in, the addon captures ALL chat messages during a short window (default 1 second). Addon messages are blocked during this window, while system messages are allowed through.

If `/reload` is used while you're already inside a dungeon or raid, there's no login spam to catch, so CleanStart detects this and skips the capture window entirely rather than running it against live instance chat.

### Message Types

The addon distinguishes between two message types:

1. **Addon Messages** (no message ID)
   - These are messages from addons using `print()` or direct `AddMessage` calls
   - They are **blocked during the login window** - no user action needed
   - Displayed in the GUI with a red background for information

2. **System Messages** (with message ID)
   - These include player chat and Blizzard system messages
   - **Allowed by default** - but you can choose to block specific message text
   - Displayed in the GUI with a green background
   - Show Allow/Block buttons for user choice

### Using the GUI

Type `/cs` to open the captured messages window:

- Messages are listed in chronological order
- Each message shows:
  - Type indicator ([ADDON] or [SYSTEM])
  - Message ID (for system messages)
  - The message text
  - Action buttons (for system messages only)
- For addon messages: Shows "Blocked by default" status
- For system messages: Click **Allow** or **Block** to set your preference

### Text-Based Blocking

For system messages, you have three options:

|   Button   |   Action   |
|------------|------------|
| **Allow** | Removes all matching filters for this message |
| **Block** | Blocks the exact message text (will match exactly next time) |
| **Custom** | Opens a dialog to create a custom filter |

### Custom Filter Dialog

When you click **Custom**, a dialog opens where you can:
- See the full message text (multi-line, scrollable)
- Edit the text to specify what to match
- Add prefix: `^` for starts-with match, or no prefix for contains match

**Filter Types:**
- `=text` - Exact match (what "Block" button creates)
- `^text` - Starts-with match (messages starting with this text)
- `text` - Contains match (messages containing this text anywhere)

## Commands

Use `/cleanstart` or `/cs` to interact with the addon.

| Command | Description |
|---------|-------------|
| `/cs` | Toggle the captured messages window |
| `/cs on\|off` | Enable/disable filtering |
| `/cs status` | Show current status |
| `/cs window <secs>` | Set capture window duration (default: 1s) |
| `/cs list` | List all custom filters |
| `/cs add <text>` | Add filter manually (^starts, =exact) |
| `/cs remove <#>` | Remove a filter by number |
| `/cs clearfilters` | Clear all filters |
| `/cs whitelist add | remove | list <text>` | Manage whitelist |
| `/cs debug` | Toggle debug output |

## Filter Priority

Messages are processed in this order:

1. **CleanStart's own messages** - Always allowed
2. **Whitelist** - If matched, message is allowed
3. **Custom text filters** - If matched, message is blocked
4. **Addon messages** (no ID) - Blocked during login window only
5. **System messages** - Always allowed (unless blocked by text filter)

## Custom Text Filters

Filters are created automatically when you click "Exact" or "Similar" in the GUI. You can view them with `/cs list` and remove them with `/cs remove <#>`.

**Filter Types:**
- `=text` - Exact match (created by "Exact" button)
- `^text` - Starts-with match (created by "Similar" button)
- `text` - Contains match (for manual use via `/cs add`)

**Manual Examples:**
```
/cs add DBM                    - Contains "DBM" anywhere
/cs add ^Remember              - Starts with "Remember"
```

## Whitelist

Ensure specific messages are never blocked. Matching is **case-insensitive**:
```
/cs whitelist add MyAddon
/cs whitelist add [Raid]
```

## Configuration

Settings are saved per-account in `SavedVariables` and persist between sessions:

- `enabled` - Master toggle for all filtering
- `debug` - Show debug messages with message IDs
- `blockWindow` - Duration of capture window in seconds
- `customFilters` - List of custom text filters (includes blocked message texts)
- `whitelist` - List of whitelisted text patterns

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
  Capture window : 1s
  Custom filters : 0
  Whitelist entries : 0
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

- Works with all chat frames with the **default interface**
- Not fully compatible with ElvUI - message capture may be incomplete or inconsistent when ElvUI is active

## License

This addon is provided as-is for personal use in World of Warcraft.
