// Real producer measurements and real Node/Git/filesystem boundaries.
// The action/history envelopes below are intentional refusal-test fixtures:
// they exercise strict channel/source/history rules without a GitHub action or
// remote publication. They preserve actual measured tuples, are never reference
// baselines, and make no network requests or pushes. Genuine immutable-action
// integration is qualified separately; these unit fixtures cannot replace it.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { packageMeasurements } from './package-benchmark-directions.mjs';
import { verifyPublication } from './verify-benchmark-publication.mjs';

const [rawFile, descriptorFile, source] = process.argv.slice(2);
assert(rawFile && descriptorFile && /^[0-9a-f]{40}$/.test(source), 'actual measured source and artifacts required');
const originalBytes = fs.readFileSync(rawFile);
const raw = JSON.parse(originalBytes);
const descriptors = JSON.parse(fs.readFileSync(descriptorFile, 'utf8'));
const channels = packageMeasurements(descriptors, raw, true);
const tagged = [...channels.smaller, ...channels.bigger];
const copy = value => structuredClone(value);
const tuples = values => values.map(({name, unit, value}) => ({name, unit, value})).sort((a,b) => a.name.localeCompare(b.name));

test('twenty genuine tuples conserved across sixteen smaller and four bigger channels', () => {
  assert.equal(channels.smaller.length, 16);
  assert.equal(channels.bigger.length, 4);
  assert.deepEqual(tuples(tagged), tuples(raw));
  assert.deepEqual(packageMeasurements(descriptors, tagged), channels);
  assert(originalBytes.equals(fs.readFileSync(rawFile)), 'raw measured artifact changed');
});
for (const [name, mutate] of [
  ['missing measurement', v => v.pop()],
  ['additional measurement', v => v.push(copy(v[0]))],
  ['duplicate name', v => { v[1].name = v[0].name; }],
  ['unknown name', v => { v[0].name = 'unknown metric'; }],
  ['wrong unit', v => { v[0].unit = 'invalid unit'; }],
  ['nonfinite value', v => { v[0].value = Infinity; }],
  ['malformed value', v => { v[0].value = 'not a measurement'; }],
  ['contradictory direction', v => { v[0].extra = v[0].extra.replace('target<=', 'target>='); }],
  ['duplicate direction token', v => { v[0].extra += '; target<='; }],
  ['missing ordinary direction', v => { v[0].extra = ''; }],
]) test(`strict packager refuses ${name}`, () => {
  const invalid = copy(tagged); mutate(invalid);
  assert.throws(() => packageMeasurements(descriptors, invalid));
});
test('duplicate descriptors refused and legacy bridge is explicit', () => {
  const invalid = copy(descriptors); invalid[1] = copy(invalid[0]);
  assert.throws(() => packageMeasurements(invalid, tagged));
  const untagged = tagged.map(v => ({...v, extra: ''}));
  assert.throws(() => packageMeasurements(descriptors, untagged));
  assert.deepEqual(tuples([...packageMeasurements(descriptors, untagged, true).smaller,
                           ...packageMeasurements(descriptors, untagged, true).bigger]), tuples(raw));
});

const suite = 'isonim-tui Performance (Linux)';
const fixture = callback => {
  const owned = fs.mkdtempSync(path.join(os.tmpdir(), 'tui-benchmark-contract-'));
  const repo = path.join(owned, 'repo'); fs.mkdirSync(repo);
  const git = (...args) => execFileSync('git', ['-C', repo, ...args], {encoding:'utf8'}).trim();
  const commit = message => {
    git('add', '--all');
    git('-c', 'user.name=benchmark-contract-fixture', '-c', 'user.email=fixture@example.invalid',
        '-c', 'commit.gpgsign=false', 'commit', '-m', message);
  };
  const write = (channel, data) => {
    fs.mkdirSync(path.join(repo, channel), {recursive:true});
    fs.writeFileSync(path.join(repo, channel, 'data.js'), 'window.BENCHMARK_DATA = ' + JSON.stringify(data) + '\n');
  };
  try {
    git('init');
    const datasets = {};
    for (const [channel, tool, benches] of [
      ['perf/bench','customSmallerIsBetter',channels.smaller],
      ['perf/bench-bigger','customBiggerIsBetter',channels.bigger],
    ]) {
      datasets[channel] = {entries:{[suite]:[{commit:{id:source},tool,benches:copy(benches)}]}};
      write(channel, datasets[channel]);
    }
    fs.writeFileSync(path.join(repo, 'README.md'), 'Owned contract fixture, not a reference baseline.\n');
    commit('Fixture previous history'); const parent = git('rev-parse', 'HEAD');
    for (const channel of Object.keys(datasets)) {
      datasets[channel].entries[suite].push(copy(datasets[channel].entries[suite][0]));
      write(channel, datasets[channel]);
    }
    commit('Fixture next channel records');
    const small = path.join(owned,'smaller.json'), big = path.join(owned,'bigger.json');
    fs.writeFileSync(small, JSON.stringify(channels.smaller));
    fs.writeFileSync(big, JSON.stringify(channels.bigger));
    callback({repo,git,commit,write,datasets,parent,small,big});
  } finally { fs.rmSync(owned, {recursive:true}); }
};
test('publication verifier preserves complete genuine tuples and historical records', () => fixture(f => {
  assert.deepEqual(verifyPublication(f.repo, source, f.parent, f.small, f.big).counts, [16,4]);
}));
for (const [name, mutate, diagnostic] of [
  ['wrong data source', f => {}, undefined],
  ['non-channel mutation', f => { fs.appendFileSync(path.join(f.repo,'README.md'),'unexpected\n'); f.commit('Wrong outside channel'); }, /non-channel/],
  ['measured tuple corruption', f => { f.datasets['perf/bench'].entries[suite].at(-1).benches[0].value += 1; f.write('perf/bench',f.datasets['perf/bench']); f.commit('Wrong measured tuple'); }, undefined],
  ['history loss', f => { f.datasets['perf/bench'].entries[suite].shift(); f.write('perf/bench',f.datasets['perf/bench']); f.commit('Wrong lost history'); }, /history|Expected/],
  ['unexpected suite', f => { f.datasets['perf/bench'].entries.unexpected = []; f.write('perf/bench',f.datasets['perf/bench']); f.commit('Wrong suite'); }, /unexpected suite/],
]) test(`publication verifier refuses ${name}`, () => fixture(f => {
  mutate(f);
  const expected = name === 'wrong data source' ? '0'.repeat(40) : source;
  assert.throws(() => verifyPublication(f.repo, expected, f.parent, f.small, f.big), diagnostic);
}));
