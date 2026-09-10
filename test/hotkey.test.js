// node test/hotkey.test.js — exercises HotkeyModel.js without Qt.
const fs = require('fs'), path = require('path'), assert = require('assert')
const src = fs.readFileSync(path.join(__dirname, '..', 'HotkeyModel.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
const H = {}
new Function('exports', src + '\n' + ['OWNER','DEFAULT_HOTKEY','CANDIDATES','parseCombo','formatCombo','pretty','parseBinds','status','ourCombos','resolve','luaBind','luaUnbind','luaBindUser','applyScript','releaseScript','parseSettings','serializeSettings','summary'].map(n => `exports.${n} = ${n}`).join('\n'))(H)

// parseCombo
let p = H.parseCombo('super+alt+b')
assert.equal(p.error, ''); assert.equal(p.mods, 72); assert.equal(p.key, 'B'); assert.equal(p.combo, 'SUPER + ALT + B')
assert.equal(H.parseCombo('SHIFT + SUPER + Return').combo, 'SUPER + SHIFT + RETURN')
assert.equal(H.parseCombo('win + enter').combo, 'SUPER + RETURN')
assert.equal(H.parseCombo('SUPER + F5').combo, 'SUPER + F5')
assert.equal(H.parseCombo('F12').combo, 'F12')                 // F keys need no modifier
assert.equal(H.parseCombo('super + code:34').combo, 'SUPER + code:34')
assert.equal(H.parseCombo('SUPER + XF86Calculator').combo, 'SUPER + XF86Calculator')
assert(H.parseCombo('').error); assert(H.parseCombo('SUPER +').error)
assert(H.parseCombo('B').error)                                // bare letter would hijack typing
assert(H.parseCombo('SUPER + B + C').error)
assert(H.parseCombo('SUPER + bogus').error)
assert.equal(H.pretty('SUPER + ALT + B'), 'Super+Alt+B')
assert.equal(H.pretty('SUPER + SPACE'), 'Super+Space')
assert.equal(H.pretty('SUPER + ALT + SLASH'), 'Super+Alt+/')

// parseBinds on real hyprctl output shape
const bindsText = `bindd
\tmodmask: 65
\tsubmap:
\tkey: B
\tkeycode: 0
\tcatchall: false
\tdescription: Browser
\tdispatcher: __lua
\targ: 276

bindd
\tmodmask: 64
\tsubmap:
\tkey: B
\tkeycode: 0
\tcatchall: false
\tdescription: ${H.OWNER}
\tdispatcher: __lua
\targ: 300

bind
\tmodmask: 64
\tsubmap: resize
\tkey: B
\tkeycode: 0
\tcatchall: false
\tdescription:
\tdispatcher: resizeactive
\targ: 10 0

bindd
\tmodmask: 68
\tsubmap:
\tkey:
\tkeycode: 34
\tcatchall: false
\tdescription: Code key
\tdispatcher: __lua
\targ: 5
`
const binds = H.parseBinds(bindsText)
assert.equal(binds.length, 4)
assert.equal(binds[0].modmask, 65); assert.equal(binds[0].key, 'B'); assert.equal(binds[0].description, 'Browser')
assert.equal(binds[2].submap, 'resize')
assert.deepEqual(H.status(binds, 'SUPER + SHIFT + B'), { state: 'taken', owner: 'Browser' })
assert.deepEqual(H.status(binds, 'SUPER + B'), { state: 'ours', owner: '' })      // submap bind ignored
assert.deepEqual(H.status(binds, 'SUPER + ALT + B'), { state: 'free', owner: '' })
assert.deepEqual(H.status(binds, 'SUPER + CTRL + code:34'), { state: 'taken', owner: 'Code key' })
assert.deepEqual(H.ourCombos(binds), ['SUPER + B'])
assert.equal(H.parseBinds('').length, 0)

// resolve: preferred free/ours → keep; taken → first free candidate, naming the owner
let r = H.resolve(binds, 'SUPER + B')
assert.equal(r.target, 'SUPER + B'); assert.equal(r.fallback, false); assert.equal(r.preferredOwner, '')
r = H.resolve(binds, 'SUPER + SHIFT + B')
assert.equal(r.target, 'SUPER + B'); assert.equal(r.fallback, true); assert.equal(r.preferredOwner, 'Browser')
const noOurs = binds.filter(b => b.description !== H.OWNER)
const taken = noOurs.concat(H.parseBinds(H.CANDIDATES.map((c, i) => {
  const q = H.parseCombo(c); return `bindd\n\tmodmask: ${q.mods}\n\tsubmap: \n\tkey: ${q.key}\n\tkeycode: 0\n\tcatchall: false\n\tdescription: Other ${i}\n\tdispatcher: __lua\n\targ: 1\n`
}).join('\n')))
r = H.resolve(taken, 'SUPER + B')
assert.equal(r.target, ''); assert.equal(r.preferredOwner, 'Other 0')
assert.equal(H.resolve([], 'garbage').preferred, H.DEFAULT_HOTKEY)   // invalid preferred → default

// scripts
const cmd = 'omarchy-shell shell toggle io.github.decadentsavant.bookmark-everything'
assert.equal(H.luaBind('SUPER + B', cmd), `o.bind("SUPER + B", "${H.OWNER}", "${cmd}")`)
assert.equal(H.luaUnbind('SUPER + B'), 'hl.unbind("SUPER + B")')
assert.equal(H.luaBindUser('SUPER + B', 'io.github.decadentsavant.bookmark-everything'), 'o.bind("SUPER + B", "Bookmarks", "omarchy-shell shell toggle io.github.decadentsavant.bookmark-everything")')
assert.equal(H.applyScript(binds, 'SUPER + B', cmd), '')                              // already there
assert.equal(H.applyScript(binds, 'SUPER + ALT + B', cmd), `hl.unbind("SUPER + B"); ${H.luaBind('SUPER + ALT + B', cmd)}`)
assert.equal(H.applyScript(noOurs, 'SUPER + B', cmd), H.luaBind('SUPER + B', cmd))
assert.equal(H.releaseScript(binds), 'hl.unbind("SUPER + B")')
assert.equal(H.releaseScript(noOurs), '')
// never unbind a combo someone else also holds
const shared = binds.concat(H.parseBinds(`bindd\n\tmodmask: 64\n\tsubmap: \n\tkey: B\n\tkeycode: 0\n\tcatchall: false\n\tdescription: Theirs\n\tdispatcher: __lua\n\targ: 9\n`))
assert.equal(H.releaseScript(shared), '')
assert.equal(H.luaBind('X', 'say "hi" \\ there'), 'o.bind("X", "Bookmark Everything", "say \\"hi\\" \\\\ there")')

// settings
assert.deepEqual(H.parseSettings(''), { hotkey: 'SUPER + B', enabled: true, noticed: '', iconHidden: false, openMode: 'hints' })
assert.deepEqual(H.parseSettings('{"hotkey":"super+alt+b","enabled":false,"noticed":"x","iconHidden":true,"openMode":"search"}'), { hotkey: 'SUPER + ALT + B', enabled: false, noticed: 'x', iconHidden: true, openMode: 'search' })
assert.equal(H.parseSettings('{"hotkey":"nonsense"}').hotkey, 'SUPER + B')
assert.equal(H.parseSettings('{"openMode":"bogus","iconHidden":"nope"}').openMode, 'hints')
assert.equal(H.parseSettings('{"openMode":"bogus","iconHidden":"nope"}').iconHidden, false)
assert.equal(H.parseSettings(H.serializeSettings({ hotkey: 'SUPER + ALT + B', enabled: true })).hotkey, 'SUPER + ALT + B')
assert.deepEqual(H.parseSettings(H.serializeSettings({ hotkey: 'SUPER + B', iconHidden: true, openMode: 'search' })), { hotkey: 'SUPER + B', enabled: true, noticed: '', iconHidden: true, openMode: 'search' })

// summary
assert.equal(H.summary('SUPER + B', 'SUPER + B', '', true), 'Super+B')
assert.equal(H.summary('SUPER + ALT + B', 'SUPER + B', 'Browser', true), 'Super+Alt+B (Super+B is used by Browser)')
assert.equal(H.summary('', 'SUPER + B', 'Browser', true), 'No free hotkey; open from this icon')
assert.equal(H.summary('SUPER + B', 'SUPER + B', '', false), 'Hotkey off')

console.log('all hotkey tests passed')
