# Bookmark Everything

A keyboard-first launcher for [Omarchy](https://omarchy.org) that opens
bookmarked URLs, files, folders, and applications from a single overlay.

Press a hotkey, type a two-letter code, and the bookmark opens. Or press `/`
and search. Everything is stored in one plain JSON file on your machine. No
account, no cloud, no network access.

## Features

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
coreutils, `wl-paste`, `xdg-open`, `uwsm-app`, and `gtk-launch`. `zoxide` is
optional and only adds entries to the Places picker.

## Install

```bash
omarchy plugin add https://github.com/decadentsavant/bookmark-everything.git --enable
```

Then bind a key. Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + B", "Bookmarks", "omarchy-shell shell toggle io.github.decadentsavant.bookmark-everything")
```

Hyprland reloads the file on save. Press Super+B and you are in.

The first launch seeds a few starter bookmarks so you can see each type in
action: your home and Downloads folders, this project on GitHub, the author on
X, and one installed application. Each comes tagged so it stays useful if you
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
rm ~/.local/bin/bkmke   # only if you linked the CLI
```

Then delete the `o.bind` line from `~/.config/hypr/bindings.lua` and any
`bookmarks.*` rows you added to `omarchy-menu.jsonc`.

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
| `zz` or `?` | Open the built-in help |
| Esc | Clear a half-typed code, then close |

In Search mode the letters go into the search box and Esc clears it, then
returns to Hint mode. The other shortcuts work in both modes.

With the mouse: click a row to open it, right-click or use the `⋯` on the
highlighted row for Open / Edit / Delete, and use the `+` in the header to add.

The built-in help page (press `zz`) covers the Add dialog, path completion,
the Places picker, bulk application adding, and import/export in more detail.

## Settings

The launcher opens in Hint mode by default. To open in Search mode, set
`openMode` on the plugin's entry in `~/.config/omarchy/shell.json`:

```json
"plugins": [
  { "id": "io.github.decadentsavant.bookmark-everything", "openMode": "search" }
]
```

A key can also request a mode directly, which is handy for a second binding:

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
```

## Development

| File | Purpose |
|------|---------|
| `manifest.json` | Plugin manifest |
| `BookmarkEverything.qml` | The overlay: list, form, pickers, import/export |
| `BookmarkModel.js` | Model logic: parsing, hint assignment, fuzzy search, import merge |
| `places.sh` | Gathers entries for the Places picker |
| `help.html` | The built-in help page |
| `bkmke` | Command-line wrapper around the shell IPC |
| `test/model.test.js` | Unit tests for the model, runnable with `node` |

The model has no Qt dependencies, so its tests run anywhere:

```bash
node test/model.test.js
```

After editing plugin files, restart the shell to load them:

```bash
omarchy restart shell
```

## License

MIT. See [LICENSE](LICENSE).
