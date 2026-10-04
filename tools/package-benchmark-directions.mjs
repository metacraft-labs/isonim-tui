#!/usr/bin/env node
// Package real M24 measurements; this program never measures or invents values.
// The immutable producer descriptor corpus owns name/unit/direction. The explicit
// legacy bridge adds only comparison metadata to already measured dev entries.
import fs from 'node:fs';
import path from 'node:path';

export function packageMeasurements(descriptors, measured, allowLegacy = false) {
  if (!Array.isArray(descriptors) || descriptors.length !== 20) throw Error('required complete 20-descriptor census');
  const definitions = new Map();
  for (const d of descriptors) {
    if (!d || typeof d.name !== 'string' || !d.name || typeof d.unit !== 'string' || !d.unit || !['smaller', 'bigger'].includes(d.direction) || definitions.has(d.name)) throw Error('invalid or duplicate descriptor');
    definitions.set(d.name, d);
  }
  if (!Array.isArray(measured) || measured.length !== definitions.size) throw Error('measurement census missing or additional entry');
  const seen = new Set();
  const smaller = [], bigger = [];
  for (const entry of measured) {
    const d = definitions.get(entry?.name);
    if (!d || entry.unit !== d.unit || seen.has(entry.name) || typeof entry.value !== 'number' || !Number.isFinite(entry.value) || (entry.extra !== undefined && typeof entry.extra !== 'string')) throw Error('unknown, duplicate, malformed or wrong-unit measurement');
    seen.add(entry.name);
    const extra = entry.extra ?? '';
    const occurrences = extra.match(/target(?:<=|>=)/g) ?? [];
    const token = d.direction === 'smaller' ? 'target<=' : 'target>=';
    if (occurrences.length > 1 || (occurrences.length === 1 && occurrences[0] !== token) || (occurrences.length === 0 && !allowLegacy)) throw Error('missing or contradictory producer direction metadata');
    const packaged = occurrences.length ? { ...entry } : { ...entry, extra: extra ? `${extra}; ${token}` : token };
    (d.direction === 'smaller' ? smaller : bigger).push(packaged);
  }
  if (smaller.length !== 16 || bigger.length !== 4 || seen.size !== definitions.size || smaller.length + bigger.length !== measured.length) throw Error('direction conservation/nonempty census failed');
  return { smaller, bigger };
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(new URL(import.meta.url))) {
  const args = process.argv.slice(2);
  let allowLegacy = false;
  const options = new Map();
  const names = new Set(['--descriptors', '--input', '--smaller', '--bigger', '--descriptor-source-sha', '--data-source-sha']);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--allow-legacy-source' && !allowLegacy) { allowLegacy = true; continue; }
    if (!names.has(arg) || options.has(arg) || !args[i + 1]) throw Error('unknown, duplicate or incomplete argument');
    options.set(arg, args[++i]);
  }
  if ([...names].some(x => !options.has(x))) throw Error('all source and output arguments required');
  for (const name of ['--descriptor-source-sha', '--data-source-sha']) if (!/^[0-9a-f]{40}$/.test(options.get(name))) throw Error('immutable full source SHA required');
  const input = options.get('--input');
  const bytes = fs.readFileSync(input);
  const measured = JSON.parse(bytes);
  const result = packageMeasurements(JSON.parse(fs.readFileSync(options.get('--descriptors'), 'utf8')), measured, allowLegacy);
  const outputs = [options.get('--smaller'), options.get('--bigger')];
  if (new Set([path.resolve(input), ...outputs.map(x => path.resolve(x))]).size !== 3) throw Error('raw and both channel outputs must be distinct');
  for (const [kind, file] of [['smaller', outputs[0]], ['bigger', outputs[1]]]) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(result[kind], null, 2) + '\n');
  }
  if (!bytes.equals(fs.readFileSync(input))) throw Error('raw artifact changed');
  console.error(JSON.stringify({ descriptorSource: options.get('--descriptor-source-sha'), dataSource: options.get('--data-source-sha'), whole: measured.length, smaller: result.smaller.length, bigger: result.bigger.length }));
}
