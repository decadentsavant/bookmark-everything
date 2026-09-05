// Pure-JS model for the Omarchy Bookmarks plugin. No Qt dependencies so the
// file can be unit-tested with node and imported from QML with `.import`.
.pragma library

var TYPES = ["url", "file", "folder", "app"]
var RESERVED_HINTS = { "zz": true }   // zz always opens the plugin help
var BUILTIN_HELP_ID = "__help"

function allHints() {
  var out = []
  for (var a = 97; a <= 122; a++)
    for (var b = 97; b <= 122; b++)
      out.push(String.fromCharCode(a) + String.fromCharCode(b))
  return out
}

function isValidHint(hint) {
  return /^[a-z]{2}$/.test(String(hint || "")) && !RESERVED_HINTS[hint]
}

function isValidType(type) {
  return TYPES.indexOf(type) !== -1
}

function typeLabel(type) {
  switch (type) {
    case "url": return "URL"
    case "file": return "File"
    case "folder": return "Folder"
    case "path": return "File or folder"   // form-only choice; saved as file or folder
    case "app": return "Application"
  }
  return String(type || "")
}

function typeIcon(type) {
  switch (type) {
    case "url": return "󰧃"     // nf-md-web
    case "file": return "󰈔"    // nf-md-file
    case "folder": return "󰉋"  // nf-md-folder
    case "path": return "󰉋"    // form-only choice
    case "app": return "󰀻"     // nf-md-apps
  }
  return "󰆕"
}

function slugify(text) {
  var slug = String(text || "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
  return slug || "bookmark"
}

function uniqueId(entries, base, selfId) {
  var taken = {}
  for (var i = 0; i < entries.length; i++)
    if (entries[i].id !== selfId) taken[entries[i].id] = true
  if (!taken[base]) return base
  var n = 2
  while (taken[base + "-" + n]) n++
  return base + "-" + n
}

function normalizeTags(value) {
  var list = []
  if (Array.isArray(value)) list = value
  else if (typeof value === "string") list = value.split(/[,\s]+/)
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var tag = String(list[i] || "").trim().replace(/^#/, "").toLowerCase()
    if (!tag || seen[tag]) continue
    seen[tag] = true
    out.push(tag)
  }
  return out
}

function normalizeEntry(raw) {
  if (!raw || typeof raw !== "object") return null
  var type = String(raw.type || "").toLowerCase()
  if (type === "application") type = "app"
  if (type === "directory" || type === "dir") type = "folder"
  if (!isValidType(type)) return null
  var target = String(raw.target || raw.url || raw.path || "").trim()
  if (!target) return null
  if (type === "url") {
    if (!looksLikeUrl(target)) return null
    target = normalizeUrl(target)
  }
  var name = String(raw.name || raw.title || "").trim() || target
  var hint = String(raw.hint || "").toLowerCase().trim()
  return {
    id: String(raw.id || "").trim(),
    hint: isValidHint(hint) ? hint : "",
    type: type,
    name: name,
    target: target,
    tags: normalizeTags(raw.tags),
    notes: String(raw.notes || "").trim()
  }
}

// Fill in missing ids and hints, and resolve duplicate hints (first entry
// keeps the code, later ones are bumped to the next free code). Returns
// { entries, changed } where changed says whether anything was rewritten.
function normalizeAll(entries) {
  var out = []
  var changed = false
  var usedHints = {}
  var i
  for (i = 0; i < entries.length; i++) {
    var e = normalizeEntry(entries[i])
    if (!e) { changed = true; continue }
    if (!e.id) { e.id = slugify(e.name); changed = true }
    e.id = uniqueId(out, e.id)
    if (e.id !== String(entries[i].id || "")) changed = true
    if (e.hint && usedHints[e.hint]) { e.hint = ""; changed = true }
    if (e.hint) usedHints[e.hint] = true
    out.push(e)
  }
  for (i = 0; i < out.length; i++) {
    if (out[i].hint) continue
    out[i].hint = nextFreeHint(out, out[i].id)
    usedHints[out[i].hint] = true
    changed = true
  }
  return { entries: out, changed: changed }
}

function parseBookmarks(rawText) {
  var data = null
  try { data = JSON.parse(String(rawText || "").trim() || "[]") } catch (e) { return { entries: [], changed: false, error: String(e) } }
  var list = Array.isArray(data) ? data : (data && Array.isArray(data.bookmarks) ? data.bookmarks : null)
  if (!list) return { entries: [], changed: false, error: "Expected a JSON array of bookmarks" }
  var result = normalizeAll(list)
  result.error = ""
  return result
}

function serialize(entries) {
  var clean = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    clean.push({ id: e.id, hint: e.hint, type: e.type, name: e.name, target: e.target, tags: e.tags || [], notes: e.notes || "" })
  }
  return JSON.stringify(clean, null, 2) + "\n"
}

function nextFreeHint(entries, excludeId) {
  var used = {}
  for (var i = 0; i < entries.length; i++)
    if (entries[i].id !== excludeId && entries[i].hint) used[entries[i].hint] = true
  var hints = allHints()
  for (var j = 0; j < hints.length; j++) {
    if (RESERVED_HINTS[hints[j]] || used[hints[j]]) continue
    return hints[j]
  }
  return ""   // more than 675 entries: search-only
}

// Insert or replace `entry` in `entries`. If its hint collides with another
// entry, the two swap: the other entry takes `displacedHint` (the code this
// entry had before, or the code it would have been auto-assigned) when that
// code is valid and free, otherwise the next free code. Returns
// { entries, swapped } where swapped is the displaced entry or null.
function upsert(entries, entry, displacedHint) {
  var out = []
  var replaced = false
  var swapped = null
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].id === entry.id) { out.push(entry); replaced = true }
    else out.push(entries[i])
  }
  if (!replaced) out.push(entry)
  for (var j = 0; j < out.length; j++) {
    if (out[j].id === entry.id || !entry.hint) continue
    if (out[j].hint === entry.hint) {
      out[j] = cloneEntry(out[j])
      var preferred = String(displacedHint || "")
      out[j].hint = (isValidHint(preferred) && hintOwner(out, preferred) === null) ? preferred : nextFreeHint(out, out[j].id)
      swapped = out[j]
    }
  }
  return { entries: out, swapped: swapped }
}

function removeById(entries, id) {
  var out = []
  for (var i = 0; i < entries.length; i++) if (entries[i].id !== id) out.push(entries[i])
  return out
}

function cloneEntry(e) {
  return { id: e.id, hint: e.hint, type: e.type, name: e.name, target: e.target, tags: (e.tags || []).slice(), notes: e.notes || "" }
}

function sortByHint(entries) {
  var out = entries.slice()
  out.sort(function(a, b) {
    var ah = a.hint || "~~", bh = b.hint || "~~"
    if (ah < bh) return -1
    if (ah > bh) return 1
    return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1
  })
  return out
}

// Merge an imported list into the existing one. Same id → replace in place,
// otherwise append. Imported hints that collide with existing entries are
// reassigned so existing codes stay stable.
function mergeImport(existing, imported) {
  var out = existing.slice()
  var added = 0, updated = 0
  var byId = {}
  for (var i = 0; i < out.length; i++) byId[out[i].id] = i
  for (var j = 0; j < imported.length; j++) {
    var e = cloneEntry(imported[j])
    if (!isValidHint(e.hint)) e.hint = ""
    if (byId[e.id] !== undefined) {
      var prev = out[byId[e.id]]
      if (!e.hint || (hintOwner(out, e.hint) !== null && hintOwner(out, e.hint) !== e.id)) e.hint = prev.hint
      out[byId[e.id]] = e
      updated++
    } else {
      if (!e.hint || hintOwner(out, e.hint) !== null) e.hint = nextFreeHint(out, e.id)
      byId[e.id] = out.length
      out.push(e)
      added++
    }
  }
  return { entries: out, added: added, updated: updated }
}

function hintOwner(entries, hint) {
  for (var i = 0; i < entries.length; i++) if (entries[i].hint === hint) return entries[i].id
  return null
}

// ----------------------------------------------------------------- targets

function looksLikeUrl(text) {
  var t = String(text || "").trim()
  if (!t || /\s/.test(t)) return false
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(t)) return true
  if (/^(mailto|tel|sms|geo):/i.test(t)) return true
  return /^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?(\/[^\s]*)?$/i.test(t)
}

function looksLikePath(text) {
  var t = String(text || "").trim()
  return /^(\/|~\/|~$|\$HOME\/)/.test(t) || /^file:\/\//i.test(t)
}

function normalizeUrl(text) {
  var t = String(text || "").trim()
  if (!/^[a-z][a-z0-9+.-]*:/i.test(t)) t = "https://" + t
  return t
}

function expandPath(text, home) {
  var t = String(text || "").trim()
  if (/^file:\/\//i.test(t)) {
    t = t.replace(/^file:\/\//i, "")
    try { t = decodeURIComponent(t) } catch (e) { }
  }
  if (t === "~") return home
  if (t.indexOf("~/") === 0) return home + t.slice(1)
  if (t.indexOf("$HOME/") === 0) return home + t.slice(5)
  return t
}

function compactPath(text, home) {
  var t = String(text || "")
  if (home && t.indexOf(home + "/") === 0) return "~" + t.slice(home.length)
  if (home && t === home) return "~"
  return t
}

// Guess a bookmark type from a pasted target. Returns "url", "path" (file
// or folder — the caller stats it to decide), or "".
function detectTarget(text) {
  if (looksLikePath(text)) return "path"
  if (looksLikeUrl(text)) return "url"
  return ""
}

// ------------------------------------------------------------------ search

function searchText(entry) {
  return [entry.name, (entry.tags || []).join(" "), entry.notes || "", entry.target, entry.appName || ""].join("\n").toLowerCase()
}

function subsequenceScore(haystack, needle) {
  // Ordered subsequence match with a bonus for consecutive characters and
  // word-start hits. Returns -1 when needle is not a subsequence.
  var hi = 0, score = 0, streak = 0
  for (var ni = 0; ni < needle.length; ni++) {
    var idx = haystack.indexOf(needle[ni], hi)
    if (idx === -1) return -1
    if (idx === hi && ni > 0) { streak++; score += 3 + streak }
    else { streak = 0; score += 1 }
    if (idx === 0 || /[\s\/._\-#]/.test(haystack[idx - 1])) score += 2
    hi = idx + 1
  }
  return score
}

function prepareSearch(entries) {
  for (var i = 0; i < entries.length; i++) {
    entries[i].nameLower = entries[i].name.toLowerCase()
    entries[i].searchBlob = searchText(entries[i])
  }
  return entries
}

function scoreEntry(entry, terms) {
  var name = entry.nameLower || entry.name.toLowerCase()
  var all = entry.searchBlob || searchText(entry)
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var term = terms[i]
    var best = -1
    if (name === term) best = 200
    else if (name.indexOf(term) === 0) best = 120
    else if (name.indexOf(term) !== -1) best = 80
    else if (entry.hint === term) best = 150
    else if (all.indexOf(term) !== -1) best = 40
    else {
      var s = subsequenceScore(name, term)
      if (s >= 0) best = 10 + s
      else {
        var s2 = subsequenceScore(all, term)
        if (s2 >= 0) best = 1 + Math.min(s2, 8)
      }
    }
    if (best < 0) return -1
    total += best
  }
  return total
}

function search(entries, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  var terms = q ? q.split(/\s+/) : []
  var rows = []
  for (var i = 0; i < entries.length; i++) {
    var score = terms.length ? scoreEntry(entries[i], terms) : 0
    if (score < 0) continue
    rows.push({ entry: entries[i], score: score, order: i })
  }
  rows.sort(function(a, b) {
    if (a.score !== b.score) return b.score - a.score
    return a.order - b.order
  })
  var out = []
  for (var j = 0; j < rows.length && (!limit || j < limit); j++) out.push(rows[j].entry)
  return out
}

function hintFilter(entries, prefix) {
  if (!prefix) return entries
  var out = []
  for (var i = 0; i < entries.length; i++)
    if (entries[i].hint && entries[i].hint.indexOf(prefix) === 0) out.push(entries[i])
  return out
}

function findByHint(entries, hint) {
  for (var i = 0; i < entries.length; i++) if (entries[i].hint === hint) return entries[i]
  return null
}

function findById(entries, id) {
  for (var i = 0; i < entries.length; i++) if (entries[i].id === id) return entries[i]
  return null
}

function helpEntry(helpPath) {
  return {
    id: BUILTIN_HELP_ID,
    hint: "zz",
    type: "file",
    name: "Bookmark Everything Help",
    target: helpPath,
    tags: ["help"],
    notes: "How to use this launcher",
    builtin: true
  }
}
