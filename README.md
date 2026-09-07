# Bookmark Everything

A keyboard-first launcher for [Omarchy](https://omarchy.org) that opens
bookmarked URLs, files, folders, and applications from a single overlay.

![Bookmark Everything: the launcher in hint mode, its bar icon, and the Options screen](preview.webp)

Press a hotkey, type a two-letter code, and the bookmark opens. Or press `/`
and search. Everything is stored in one plain JSON file on your machine. No
account, no cloud, no network access.

## Features

- **Works the moment it is installed.** The plugin registers `Super+B` itself
  and puts a bookmark icon in the bar. No editing of `bindings.lua`. If
  `Super+B` is already taken, it picks a free key, tells you which, and the
  icon's tooltip always shows the current one.
- **Hint mode.** Every bookmark has a stable two-letter code shown beside it.
  Type the code and it opens immediately.
- **Search mode.** Fuzzy search across name, tags, notes, URL or path, and
  application name. Fast with a thousand entries.
- **Four bookmark types.** URLs open in your browser, files in their default
  application, folders in your file manager, and applications launch the same
  way they do from the Omarchy app menu.
- **Add, edit, delete** from the keyboard or the mouse. Paste a URL or a path
  and the type is detected. Paths complete with Tab, like a shell.
- **Add applications in bulk.** Pick several installed applications at once,
  or all of them.
- **Places picker.** Choose from folders and files you already use: your file
  manager's sidebar bookmarks, your most-visited directories, and recent files.
- **Import and export** as JSON. Your existing file is backed up before an
  import.
- **Looks like Omarchy.** Uses the shell's own theme, fonts, spacing, and
  selection colors, so it matches whatever theme you run.

## Requirements

Omarchy 4.0 or newer. Everything the plugin calls ships with Omarchy: bash,
coreutils, `hyprctl`, `wl-paste`, `xdg-open`, `uwsm-app`, and `gtk-launch`.
`zoxide` is optional and only adds entries to the Places picker.

## Install

```bash
omarchy plugin add https://github.com/decadentsavant/bookmark-everything.git --enable
```

That is all. Press **Super+B** and you are in. A bookmark icon also appears
in the bar (you are asked which section): click it to open the launcher,
hover it to see the current hotkey, right-click it for options.

If `Super+B` is already bound on your machine, the plugin uses the first free
key from a short list (`Super+Alt+B` first) and sends one notification saying
which. Change it any time: right-click the bar icon, or click the gear at the
bottom of the launcher. See [Hotkey](#hotkey) below.

The first launch seeds a few starter bookmarks so you can see each type in
action: your home and Downloads folders, this project and Baton on GitHub, the
author on X, and one installed application. Each comes tagged so it stays useful if you
keep it. Edit or delete them as you like. The `zz` entry is the built-in help
and is always there.

### Optional: command line

The plugin ships a small CLI called `bkmke`. Put it on your PATH:

```bash
ln -s ~/.config/omarchy/plugins/io.github.decadentsavant.bookmark-everything/bkmke ~/.local/bin/bkmke
```

```
bkmke                    toggle the launcher
bkmke search             open straight into Search mode
bkmke add .              bookmark the current folder
bkmke add <url-or-path>  open the Add dialog with the target filled in
bkmke clip               add whatever URL or path is on the clipboard
bkmke apps               pick installed applications to add
bkmke import <file>      merge a JSON export
bkmke export [file]      write all bookmarks to a JSON file
bkmke hotkey [combo|off] show the hotkey, set one ("SUPER + ALT + B"), or turn it off
bkmke icon on|off        show or hide the bookmark icon in the bar
bkmke options            open the options screen
```

### Optional: Omarchy menu entries

To reach the launcher from the Omarchy menu as well, add these rows to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"bookmarks": {"icon":"󰃀","label":"Bookmarks"},
"bookmarks.open": {"icon":"󰃀","label":"Open","action":"omarchy-shell shell summon io.github.decadentsavant.bookmark-everything '{}'"},
"bookmarks.search": {"icon":"","label":"Search","action":"omarchy-shell shell summon io.github.decadentsavant.bookmark-everything '{\"mode\":\"search\"}'"},
"bookmarks.add": {"icon":"","label":"Add bookmark","action":"omarchy-shell shell call io.github.decadentsavant.bookmark-everything addBookmark ''"},
"bookmarks.apps": {"icon":"󰀻","label":"Add applications","action":"omarchy-shell shell call io.github.decadentsavant.bookmark-everything pickApplications ''"},
"bookmarks.clipboard": {"icon":"󰅌","label":"Add from clipboard","action":"omarchy-shell shell call io.github.decadentsavant.bookmark-everything addFromClipboard ''"}
```

## Remove

```bash
omarchy plugin remove io.github.decadentsavant.bookmark-everything
```

That disables the plugin and deletes its folder. Your bookmarks are kept on
purpose. To remove everything the plugin touched:

```bash
rm ~/.config/omarchy/bookmark-everything.json ~/.config/omarchy/bookmark-everything.json.bak-*
rm ~/.config/omarchy/bookmark-everything.settings.json   # exists only if you changed the hotkey
rm ~/.local/bin/bkmke                                     # only if you linked the CLI
```

The hotkey is unregistered when the plugin is disabled or removed; it was
never written to `~/.config/hypr`. If you added `bookmarks.*` rows to
`omarchy-menu.jsonc` or a binding of your own to `bindings.lua`, delete those.

## Using it

| Key | Hint mode |
|-----|-----------|
| `a`…`z` twice | Open the bookmark with that code |
| `/` or Tab | Switch to Search mode |
| ↑ ↓ then Enter | Move the highlight and open it |
| `+` or Ctrl+N | Add a bookmark |
| Ctrl+V | Add the URL or path on the clipboard |
| Ctrl+A | Add installed applications in bulk |
| Ctrl+E | Edit the highlighted bookmark |
| Delete, Backspace, or Ctrl+D | Delete the highlighted bookmark, with confirmation (Backspace: Hint mode only) |
| Ctrl+I / Ctrl+O | Import / export |
| Ctrl+K or the gear at the bottom | Options: the hotkey and the bar icon |
| `zz` or `?` | Open the built-in help |
| Esc | Clear a half-typed code, then close |

In Search mode the letters go into the search box and Esc clears it, then
returns to Hint mode. The other shortcuts work in both modes.

With the mouse: click a row to open it, right-click or use the `⋯` on the
highlighted row for Open / Edit / Delete, and use the `+` in the header to add.

The built-in help page (press `zz`) covers the Add dialog, path completion,
the Places picker, bulk application adding, and import/export in more detail.

## Hotkey

The plugin registers its key in the running compositor with `hyprctl eval`,
the same call Omarchy's own Lua config uses. Nothing under `~/.config/hypr`
is written, and the key is unregistered when the plugin is disabled or
removed. Hyprland rebuilds its bindings from your config on `hyprctl reload`;
the plugin notices and puts its key back.

- **Preferred key:** `Super+B`. If that is taken, the first free one of
  `Super+Alt+B`, `Super+Ctrl+Alt+B`, `Super+Alt+M`, `Super+Alt+U`,
  `Super+Alt+/` is used and you get one notification saying so.
- **See it:** hover the bookmark icon in the bar. `Super+K` (Omarchy's
  keybindings menu) lists it too, as "Bookmark Everything".
- **Change it:** right-click the bar icon, or click the gear at the bottom of
  the launcher (`Ctrl+K`). The Options screen shows what opens the launcher
  now; type a combination such as `SUPER + ALT + B` and press Enter. A key
  something else already uses is refused, with the reason. Nothing is
  captured from a key press, because Hyprland would act on a bound
  combination before the launcher could see it.
- **Turn it off:** the *Built-in hotkey* toggle on the same screen, or
  `bkmke hotkey off`. The screen then shows the exact line to add to
  `~/.config/hypr/bindings.lua` if you want to bind it yourself:

  ```lua
  o.bind("SUPER + B", "Bookmarks", "omarchy-shell shell toggle io.github.decadentsavant.bookmark-everything")
  ```

  A binding of your own is also detected: if `Super+B` is already bound when
  the plugin loads, the plugin leaves it alone rather than doubling it.
- **Hide the bar icon:** the *Icon in the bar* toggle, or `bkmke icon off`.
  The launcher stays loaded and the hotkey keeps working; the screen reminds
  you that the hotkey is then the only way in.
- **Take over a key that is in use:** free it first in
  `~/.config/hypr/bindings.lua`, for example `hl.unbind("SUPER + B")`, then
  choose it in the launcher.

Your choice is stored in `~/.config/omarchy/bookmark-everything.settings.json`
(`hotkey`, `enabled`). The file is created the first time you change
something.

## Settings

The launcher opens in Hint mode by default. To open in Search mode, set
`openMode` on the plugin's entry in `~/.config/omarchy/shell.json`:

```json
"plugins": [
  { "id": "io.github.decadentsavant.bookmark-everything", "openMode": "search" }
]
```

A second key of your own can request a mode directly:

```lua
o.bind("SUPER + SHIFT + B", "Bookmark search", "omarchy-shell shell summon io.github.decadentsavant.bookmark-everything '{\"mode\":\"search\"}'")
```

## Storage

Bookmarks live in `~/.config/omarchy/bookmark-everything.json`, a JSON array
you can edit by hand. The launcher reloads it on save and fills in any missing
ids or hint codes.

```json
{
  "id": "arch-wiki",
  "hint": "aa",
  "type": "url",
  "name": "Arch Wiki",
  "target": "https://wiki.archlinux.org",
  "tags": ["linux", "reference"],
  "notes": "Pacman and everything else"
}
```

`type` is one of `url`, `file`, `folder`, or `app`. For `app`, `target` is the
desktop entry id, such as `org.gnome.Nautilus`. Paths may start with `~/`.

Import uses the same format. Entries with a matching `id` are replaced, new
ones are appended, and an imported hint that collides with an existing one is
reassigned so your codes stay stable. A timestamped backup of the previous file
is written next to it before every import.

## Shell IPC

Everything the CLI does goes through the Omarchy shell's IPC and can be
scripted directly:

```
omarchy-shell shell toggle io.github.decadentsavant.bookmark-everything
omarchy-shell shell summon io.github.decadentsavant.bookmark-everything '{"mode":"search"}'
omarchy-shell shell call io.github.decadentsavant.bookmark-everything addBookmark <target>
omarchy-shell shell call io.github.decadentsavant.bookmark-everything addFromClipboard ''
omarchy-shell shell call io.github.decadentsavant.bookmark-everything pickApplications ''
omarchy-shell shell call io.github.decadentsavant.bookmark-everything importFrom <path>
omarchy-shell shell call io.github.decadentsavant.bookmark-everything exportTo <path>
omarchy-shell shell summon io.github.decadentsavant.bookmark-everything '{"options":true}'
omarchy-shell shell call io.github.decadentsavant.bookmark-everything hotkeyStatus ''
omarchy-shell shell call io.github.decadentsavant.bookmark-everything setHotkey 'SUPER + ALT + B'
omarchy-shell shell call io.github.decadentsavant.bookmark-everything setHotkeyEnabled false
omarchy-shell shell call io.github.decadentsavant.bookmark-everything setIconInBar false
```

## Development

| File | Purpose |
|------|---------|
| `manifest.json` | Plugin manifest |
| `BookmarkEverything.qml` | The overlay: list, form, pickers, import/export, options |
| `BookmarkModel.js` | Model logic: parsing, hint assignment, fuzzy search, import merge |
| `BookmarkBarWidget.qml` | The bar icon |
| `HotkeyService.qml` | Singleton that registers the hotkey and keeps it in place |
| `HotkeyModel.js` | Hotkey logic: combo parsing, `hyprctl binds` parsing, fallback choice, Lua generation |
| `qmldir` | Declares the singleton for the overlay and the bar widget |
| `places.sh` | Gathers entries for the Places picker |
| `help.html` | The built-in help page |
| `bkmke` | Command-line wrapper around the shell IPC |
| `test/model.test.js`, `test/hotkey.test.js` | Unit tests for the two models, runnable with `node` |
| `dev/listing.sh`, `dev/listing/` | Renders `preview.webp`, the marketplace card, from real screenshots |

`preview.webp` is a 2000×1000 card rendered from `dev/listing/listing.html`
with headless Chromium and ImageMagick. It embeds unedited screenshots of the
launcher, the Options screen, and the icon in the bar (`dev/listing/*.png`);
the title, feature list, and colours are presentation artwork. Retake the
screenshots and run `./dev/listing.sh` when the UI changes.

The models have no Qt dependencies, so their tests run anywhere:

```bash
node test/model.test.js
node test/hotkey.test.js
```

After editing plugin files, restart the shell to load them:

```bash
omarchy restart shell
```

## License

MIT. See [LICENSE](LICENSE).
