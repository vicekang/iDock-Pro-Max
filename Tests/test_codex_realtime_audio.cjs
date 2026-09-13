// Exercise the actual shipped worklet: resampling, frame pacing, bounded queues.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(new URL('../Sources/CellDock/CodexRealtimeAudio.swift', `file://${__filename}`), 'utf8');
const script = source.match(/const worklet = `([\s\S]*?)`;/)[1];
const frames = [];
let Processor;
vm.runInNewContext(script, {
  sampleRate: 48000,
  AudioWorkletProcessor: class { constructor() { this.port = {postMessage: data => frames.push(new Int16Array(data).slice())}; } },
  registerProcessor: (_, type) => { Processor = type; },
});
const processor = new Processor();
const telephone = new Int16Array(3200).fill(8192);
processor.port.onmessage({data: telephone.buffer});
assert.equal(processor.count, 3200);
processor.port.onmessage({data: telephone.buffer});
assert.equal(processor.count, 3200, 'input queue remains bounded after overflow');
let rendered = [];
for (let i = 0; i < 15; i++) {
  const out = new Float32Array(128);
  processor.process([[new Float32Array(128).fill(0.5)]], [[out]]);
  rendered.push(...out);
}
assert.equal(frames.length, 2, '40 ms audio produces exactly two telephone frames');
for (const frame of frames) {
  assert.equal(frame.length, 160);
  assert.ok(frame.every(value => value === 16384), 'downsampled amplitude is correct');
}
assert.ok(rendered.slice(6).every(value => value === 0.25), 'outgoing telephone track has correct amplitude');
processor.count = 0;
for (let i = 0; i < 4; i++) {
  const out = new Float32Array(128); processor.process([[]], [[out]]);
  if (i > 0) assert.ok(out.every(value => value === 0), 'underrun emits silence, not stale speech');
}
console.log('Codex realtime audio: 8/48 kHz conversion, 20 ms frames, bounded queue, underrun silence passed');
