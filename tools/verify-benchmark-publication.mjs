#!/usr/bin/env node
// Verify genuine action-produced channel data and unchanged published history.
// This checker creates no measurements and makes no network calls or pushes.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

export function verifyPublication(root, source, parent, smallFile, bigFile) {
assert(root && /^[0-9a-f]{40}$/.test(source) && /^[0-9a-f]{40}$/.test(parent) && smallFile && bigFile);
const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' });
const prefix = 'window.BENCHMARK_DATA = ';
function data(text) {
  assert(text.startsWith(prefix), 'actual action data prefix required');
  return JSON.parse(text.slice(prefix.length));
}
const changed = git('diff', '--name-only', '-z', parent, 'HEAD').split('\0').filter(Boolean);
assert(changed.length > 0);
assert(changed.every(name => /^(perf\/bench|perf\/bench-bigger)\/(data\.js|index\.html)$/.test(name)), 'non-channel modification refused');
assert.equal(git('status', '--porcelain').trim(), '');
const suite = 'isonim-tui Performance (Linux)';
for (const [channel, tool, count, measuredFile] of [
  ['perf/bench', 'customSmallerIsBetter', 16, smallFile],
  ['perf/bench-bigger', 'customBiggerIsBetter', 4, bigFile],
]) {
  const actual = data(fs.readFileSync(path.join(root, channel, 'data.js'), 'utf8'));
  const records = actual.entries[suite];
  assert(Array.isArray(records) && records.length > 0);
  const latest = records.at(-1);
  assert.equal(latest.commit.id, source);
  assert.equal(latest.tool, tool);
  const measured = JSON.parse(fs.readFileSync(measuredFile, 'utf8'));
  assert.equal(measured.length, count);
  assert.equal(latest.benches.length, count);
  // The action's original comparison normalization may add comparison metadata;
  // measured names, units, values and producer extra remain unchanged.
  for (const entry of measured) {
    const matches = latest.benches.filter(item => item.name === entry.name);
    assert.equal(matches.length, 1);
    for (const key of ['name', 'unit', 'value', 'extra']) assert.deepEqual(matches[0][key], entry[key]);
  }
  const oldPath = `${parent}:${channel}/data.js`;
  const exists = execFileSync('git', ['-C', root, 'ls-tree', parent, '--', `${channel}/data.js`], { encoding: 'utf8' }).trim();
  if (exists) {
    const old = data(git('show', oldPath));
    assert.deepEqual(Object.keys(actual.entries).sort(), [...new Set([...Object.keys(old.entries), suite])].sort(), 'unexpected suite refused');
    for (const [name, entries] of Object.entries(old.entries)) {
      const retained = actual.entries[name];
      assert(Array.isArray(retained));
      assert.deepEqual(retained.slice(0, entries.length), entries, 'published history must remain');
      assert.equal(retained.length, entries.length + (name === suite ? 1 : 0));
    }
  } else {
    assert.deepEqual(Object.keys(actual.entries), [suite], 'unexpected suite refused');
  }
}
return { source, parent, counts: [16, 4], changed, clean: true };

}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(new URL(import.meta.url))) {
  console.error(JSON.stringify(verifyPublication(...process.argv.slice(2))));
}
