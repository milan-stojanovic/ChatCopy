# ChatCopy

ChatCopy is a minimal World of Warcraft addon that copies **chat tab/window configuration** (tabs + message filters + channels) between characters on the same account.

It is intentionally small:
- One dropdown: **Copy From**
- One button: **Apply** (then you confirm whether to reload)

## What gets copied
For each chat window/tab, ChatCopy copies:
- Window/tab name
- Enabled message-group filters (e.g. SAY, GUILD, WHISPER, PARTY, INSTANCE_CHAT, etc.)
- Enabled numbered chat channels per tab (best-effort, by channel name)

## What does NOT get copied
ChatCopy does **not** copy UI/visual layout settings, including:
- Tab order positioning/docking rules beyond “recreate tabs”
- Window size/position
- Fonts
- Chat bubbles/timestamps/other CVars

## How it works
- On logout, ChatCopy snapshots your current character’s chat setup into SavedVariables.
- On another character, select a source character in **Copy From**, click **Apply**, then reload when prompted.

## Installation
1. Download a release ZIP.
2. Extract into your WoW AddOns folder:
   - `_retail_/Interface/AddOns/ChatCopy/`
3. Ensure these files exist:
   - `ChatCopy.toc`
   - `ChatCopy.lua`

## Usage
1. Log onto the character that has the chat setup you want.
2. Log out / switch character (this saves a snapshot).
3. Log onto the character you want to update.
4. Open **Settings → AddOns → ChatCopy**.
5. Select the source in **Copy From** and click **Apply**.
6. Confirm the reload.

## Notes / limitations
- Applying is blocked in combat (`InCombatLockdown()`).
- Channel restoration is best-effort: if a channel cannot be joined (passworded/restricted), it may not be added.
- Debug logs are available but **disabled by default**.
  - To enable: set `ChatCopyDB.debug = true` in your SavedVariables and reload.

## License
Add your preferred license here (e.g., MIT). If you want, I can add a LICENSE file.
