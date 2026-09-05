// node test/model.test.js — exercises BookmarkModel.js without Qt.
const fs = require('fs'), path = require('path'), assert = require('assert')
const src = fs.readFileSync(path.join(__dirname, '..', 'BookmarkModel.js'), 'utf8').replace(/^\.pragma library\s*$/m, '')
const M = {}
new Function('exports', src + '\n' + ['parseBookmarks','serialize','nextFreeHint','upsert','removeById','mergeImport','search','hintFilter','detectTarget','normalizeUrl','expandPath','compactPath','isValidHint','allHints','slugify','uniqueId','normalizeTags','findByHint','prepareSearch'].map(n => `exports.${n} = ${n}`).join('\n'))(M)
assert.equal(M.allHints().length, 676)
assert.equal(M.allHints()[0], 'aa'); assert.equal(M.allHints()[675], 'zz')
assert(M.isValidHint('ab')); assert(!M.isValidHint('zz')); assert(!M.isValidHint('a1'))
let p = M.parseBookmarks(JSON.stringify([
  { id: 'pacman-cheatsheet', hint: 'aa', type: 'file', name: 'Pacman & Yay Cheatsheet', target: '/home/user/Documents/x.html', tags: ['linux','arch'], notes: 'Common' },
  { type: 'url', name: 'Dup hint', target: 'https://example.com', hint: 'aa' },
  { type: 'application', name: 'Firefox', target: 'firefox' },
  { type: 'folder', name: 'Projects folder', target: '~/Projects', hint: 'zz' },
  { type: 'bogus', name: 'x', target: 'y' },
]))
assert.equal(p.error, ''); assert.equal(p.entries.length, 4); assert(p.changed)
assert.deepEqual(p.entries.map(e => e.hint), ['aa','ab','ac','ad'])
assert.equal(p.entries[2].type, 'app'); assert.equal(p.entries[1].id, 'dup-hint')
// upsert with hint conflict bumps the other
let upr = M.upsert(p.entries, { id: 'new', hint: 'ab', type: 'url', name: 'New', target: 'https://n', tags: [], notes: '' })
let up = upr.entries
assert.equal(M.findByHint(up, 'ab').id, 'new'); assert.equal(up.find(e => e.id === 'dup-hint').hint, 'ae'); assert.equal(upr.swapped.id, 'dup-hint')
// true swap when editing: entry with 'ac' takes 'aa' → 'aa' owner gets 'ac'
let sw = M.upsert(p.entries, Object.assign({}, p.entries[2], { hint: 'aa' }), 'ac')
assert.equal(M.findByHint(sw.entries, 'aa').id, 'firefox'); assert.equal(M.findByHint(sw.entries, 'ac').id, 'pacman-cheatsheet'); assert.equal(sw.swapped.id, 'pacman-cheatsheet')
// no conflict → swapped null
assert.equal(M.upsert(p.entries, Object.assign({}, p.entries[2], { hint: 'zy' }), 'ac').swapped, null)
// nextFreeHint skips zz and used
assert.equal(M.nextFreeHint(up), 'af')
// search
let s = M.search(p.entries, 'arch'); assert.equal(s[0].id, 'pacman-cheatsheet')
s = M.search(p.entries, 'pcs'); assert.equal(s[0].id, 'pacman-cheatsheet')
s = M.search(p.entries, 'proj'); assert.equal(s[0].id, 'projects-folder')
s = M.search(p.entries, 'zzzzq'); assert.equal(s.length, 0)
assert.equal(M.search(p.entries, '').length, 4)
// hint filter
assert.equal(M.hintFilter(p.entries, 'a').length, 4); assert.equal(M.hintFilter(p.entries, 'ab').length, 1)
// detect
assert.equal(M.detectTarget('https://x.com'), 'url'); assert.equal(M.detectTarget('github.com/foo'), 'url')
assert.equal(M.detectTarget('~/Documents'), 'path'); assert.equal(M.detectTarget('/etc'), 'path'); assert.equal(M.detectTarget('hello world'), '')
assert.equal(M.normalizeUrl('github.com'), 'https://github.com'); assert.equal(M.normalizeUrl('mailto:a@b'), 'mailto:a@b')
assert.equal(M.expandPath('~/x', '/home/user'), '/home/user/x'); assert.equal(M.expandPath('file:///tmp/a%20b', '/h'), '/tmp/a b')
assert.equal(M.compactPath('/home/user/x', '/home/user'), '~/x')
// merge import
let m = M.mergeImport(p.entries, [ { id: 'pacman-cheatsheet', hint: 'zz', type: 'file', name: 'Renamed', target: '/x', tags: [], notes: '' }, { id: 'imp', hint: 'ab', type: 'url', name: 'Imp', target: 'https://i', tags: [], notes: '' } ])
assert.equal(m.updated, 1); assert.equal(m.added, 1)
assert.equal(m.entries.find(e => e.id === 'pacman-cheatsheet').hint, 'aa'); assert.equal(m.entries.find(e => e.id === 'pacman-cheatsheet').name, 'Renamed')
assert.equal(m.entries.find(e => e.id === 'imp').hint, 'ae')
// perf: 1000 entries
let big = []; for (let i = 0; i < 1000; i++) big.push({ type: 'url', name: 'Bookmark number ' + i + ' ' + Math.random().toString(36), target: 'https://site' + i + '.example.com/path', tags: ['t' + (i % 17)], notes: 'note ' + i })
let bp = M.parseBookmarks(JSON.stringify(big)); assert.equal(bp.entries.length, 1000)
assert.equal(bp.entries.filter(e => !e.hint).length, 325)
M.prepareSearch(bp.entries); let t0 = Date.now(); for (let i = 0; i < 20; i++) M.search(bp.entries, 'bkmrk 7'); console.log('20 searches over 1000 entries:', Date.now() - t0, 'ms')
assert.equal(M.normalizeTags('Linux, #arch  ref').join(','), 'linux,arch,ref')
console.log('all model tests passed')
