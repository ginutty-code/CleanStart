# !CleanStart - Clean Up Your Login Spam

Tired of login spam flooding your chat every time you enter the game? !CleanStart automatically captures, filters, and organizes all chat messages that appear during login, giving you a clean, quiet start every time you play.

Whether it's addons printing text, system messages firing all at once, or random clutter you don't care about, !CleanStart puts you in control.

You can finally filter out messages you've already seen hundreds of times, like:

> "Remember to act responsibly, protect your personal information, and report anything offensive. View our In-Game Code of Conduct..."

## Features

### Smart Message Capture

- Captures all chat messages during a short, configurable login window
- Addon messages (no message ID) are automatically blocked during this window
- System messages are allowed through but can be individually managed

### GUI Review Window

Open the interface anytime with /cs to:

- Review every captured message in order
- See message type, ID, and full text
- Allow or block any message with one click
- View addon messages (blocked by default) and choose which ones to allow

### Text-Based Filtering

Filter types include:

- =text - Exact match
- ^text - Starts-with match
- text - Contains match

### Whitelist System

Protect important messages from ever being filtered:

- Text whitelist: ensure specific lines always pass through
- Addon whitelist: exempt an entire addon so none of its login messages are blocked
- Useful for chat-skinning addons (EllesmereUI, ElvUI, etc.) that reformat chat lines

### Other

- Debug mode: see detailed message processing info, including message IDs
- Persistent settings: all filters and preferences are saved account-wide
- Lightweight: minimal performance impact
- Works in dungeons, raids and player housing

## Commands

Use /cleanstart or /cs:

- /cs - Toggle the captured messages window
- /cs on | off - Enable or disable filtering
- /cs status - Show current status
- /cs window - Set capture window duration (default: 3s)
- /cs list - List all custom filters
- /cs add - Add a filter manually (^starts, =exact)
- /cs remove <#> - Remove a filter by number
- /cs clearfilters - Clear all filters
- /cs whitelist add | remove | list - Manage the text whitelist
- /cs whitelist addon add | remove | list <name> - Manage the addon whitelist
- /cs debug - Toggle debug output

## How It Works

During login, !CleanStart captures all chat messages for a brief window.

- Addon messages are blocked by default
- System messages are shown normally
- Your Allow/Block choices are saved and applied on future logins

The same applies if you /reload inside a dungeon, raid or player housing. Messages that Blizzard marks as restricted are never inspected and always pass through untouched, and any filtering error fails open so no message is lost.

## Filter Priority

1. !CleanStart's own messages (always allowed)
2. Text whitelist
3. Custom text filters / blocked IDs
4. Addon messages (blocked during the login window)
5. Addon whitelist (exempts step 4)
6. System messages

## Compatibility

- Works best with the default Blizzard chat frames
- !CleanStart restores its chat hook only if no other addon has replaced it, so it won't overwrite chat-skin handlers
- No known conflicts with other addons

## Change Log

### 1.4.0

- Filtering now works inside all instance types (dungeons, raids, player housing) instead of being skipped after a /reload
- Restricted ("secret") chat values are never inspected and always pass through, so combat instances cannot cause errors
- Messages from addons that load before !CleanStart's login handler now stay in the /cs review window instead of being dropped from the list
- Debug output now reports the instance type at login and any skipped restricted messages

### 1.3.0

- Fixed conflicts with chat-skinning addons: the chat hook is only restored if it is still the installed one
- Added per-addon whitelist
- Addon message rows in the GUI now have Allow / Block / Custom buttons
- Filters list window now manages text whitelist and addon whitelist entries

### 1.2.x

- Default capture window increased from 1s to 3s so slower addons are caught
- Fixed silent message loss; interface version updated to 120100 / 120105
