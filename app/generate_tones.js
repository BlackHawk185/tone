#!/usr/bin/env node
/**
 * Generates psychologically-informed alert tones for Tone app.
 * 
 * Design principles (v2 — phone-speaker optimized):
 * - Fundamentals in 350–700 Hz range (phone speakers reproduce these well)
 * - Rich harmonic content for presence (not thin sine waves)
 * - Amplitude modulation (tremolo) for organic, attention-holding character
 * - Soft attack (200ms) — brain can track without startle
 * - Gradual release — signals "alert complete"
 * - Assertive but not harsh. Think cello, not smoke alarm.
 * 
 * Output: WAV files in assets/sounds/ and android/app/src/main/res/raw/
 */

const fs = require('fs');
const path = require('path');

const SAMPLE_RATE = 44100;
const BIT_DEPTH = 16;
const BYTES_PER_SAMPLE = BIT_DEPTH / 8;

// ────────────────────────────────────────────────────────────────────────
// Helper: Concatenate WAV buffers (combines audio data from multiple files)
// ────────────────────────────────────────────────────────────────────────
function concatenateWavs(wavBuffers) {
  // Sum up total data size (skip RIFF header from all but first)
  let totalDataSize = 0;
  for (let i = 0; i < wavBuffers.length; i++) {
    // Read data chunk size from each WAV (at offset 40)
    const dataSize = wavBuffers[i].readUInt32LE(40);
    totalDataSize += dataSize;
  }

  const newBuffer = Buffer.alloc(44 + totalDataSize);

  // Copy header from first WAV
  wavBuffers[0].copy(newBuffer, 0, 0, 44);

  // Update file size in header
  newBuffer.writeUInt32LE(36 + totalDataSize, 4);
  newBuffer.writeUInt32LE(totalDataSize, 40);

  // Copy all audio data, concatenated
  let offset = 44;
  for (const wav of wavBuffers) {
    const dataSize = wav.readUInt32LE(40);
    wav.copy(newBuffer, offset, 44, 44 + dataSize);
    offset += dataSize;
  }

  return newBuffer;
}

// ────────────────────────────────────────────────────────────────────────
// Helper: Generate silence (blank WAV segment)
// ────────────────────────────────────────────────────────────────────────
function generateSilence(duration) {
  const numSamples = Math.floor(SAMPLE_RATE * duration);
  const dataSize = numSamples * BYTES_PER_SAMPLE;
  const buffer = Buffer.alloc(44 + dataSize);

  // Copy header structure
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * BYTES_PER_SAMPLE, 28);
  buffer.writeUInt16LE(BYTES_PER_SAMPLE, 32);
  buffer.writeUInt16LE(BIT_DEPTH, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // All samples are zero (silence)
  for (let i = 0; i < numSamples; i++) {
    buffer.writeInt16LE(0, 44 + i * BYTES_PER_SAMPLE);
  }

  return buffer;
}

function generateWav(options) {
  const {
    duration,
    frequencies,        // [{ freq, amplitude, bend?, decay? }]
    attackTime = 0.2,
    releaseTime = 0.4,
    volume = 0.85,
    tremolo = null,     // { rate: Hz, depth: 0-1 } — amplitude modulation
    compress = 0,       // 0 = off, 1-5 = soft-clip iterations (louder average)
  } = options;

  const numSamples = Math.floor(SAMPLE_RATE * duration);
  const dataSize = numSamples * BYTES_PER_SAMPLE;
  const buffer = Buffer.alloc(44 + dataSize);

  // ── RIFF header ──
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVE', 8);

  // ── fmt chunk ──
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);               // PCM
  buffer.writeUInt16LE(1, 22);               // mono
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * BYTES_PER_SAMPLE, 28);
  buffer.writeUInt16LE(BYTES_PER_SAMPLE, 32);
  buffer.writeUInt16LE(BIT_DEPTH, 34);

  // ── data chunk ──
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // ── Generate samples ──
  const attackSamples = Math.floor(SAMPLE_RATE * attackTime);
  const releaseSamples = Math.floor(SAMPLE_RATE * releaseTime);
  const releaseStart = numSamples - releaseSamples;

  for (let i = 0; i < numSamples; i++) {
    const t = i / SAMPLE_RATE;
    const progress = i / numSamples;

    // Envelope: raised cosine attack/release
    let envelope = 1.0;
    if (i < attackSamples) {
      envelope = 0.5 * (1 - Math.cos(Math.PI * i / attackSamples));
    } else if (i > releaseStart) {
      const rp = (i - releaseStart) / releaseSamples;
      envelope = 0.5 * (1 + Math.cos(Math.PI * rp));
    }

    // Tremolo (amplitude modulation) — adds organic pulse
    let tremoloMod = 1.0;
    if (tremolo) {
      tremoloMod = 1.0 - tremolo.depth * 0.5 * (1 - Math.cos(2 * Math.PI * tremolo.rate * t));
    }

    // Sum frequency components
    let sample = 0;
    let totalAmplitude = 0;
    for (const comp of frequencies) {
      const amp = comp.amplitude || 1.0;
      totalAmplitude += amp;

      let freq = comp.freq;
      if (comp.bend) {
        freq = comp.freq + (comp.bend - comp.freq) * progress;
      }

      let compEnv = 1.0;
      if (comp.decay) {
        compEnv = Math.exp(-comp.decay * t);
      }

      sample += Math.sin(2 * Math.PI * freq * t) * amp * compEnv;
    }

    sample = (sample / totalAmplitude) * envelope * tremoloMod * volume;

    // Soft-clip compression: tanh waveshaping, iterated for more aggression
    // Each pass pushes average closer to peak without hard clipping
    for (let c = 0; c < compress; c++) {
      sample = Math.tanh(sample * 1.8) / Math.tanh(1.8);
    }

    const clamped = Math.max(-1, Math.min(1, sample));
    buffer.writeInt16LE(Math.round(clamped * 32767), 44 + i * BYTES_PER_SAMPLE);
  }

  return buffer;
}

// ────────────────────────────────────────────────────────────────────────
// TONE DEFINITIONS (v2 — phone-speaker optimized)
// ────────────────────────────────────────────────────────────────────────

const tones = {
  // PRIORITY: Steady, clear tone with body. Not urgent, but present.
  // 523 Hz (C5) + harmonics. Subtle tremolo for warmth.
  priority_tone: generateWav({
    duration: 1.8,
    attackTime: 0.15,
    releaseTime: 0.5,
    volume: 0.8,
    tremolo: { rate: 3, depth: 0.15 },
    frequencies: [
      { freq: 523, amplitude: 1.0 },               // C5
      { freq: 659, amplitude: 0.4 },               // E5 (major third)
      { freq: 785, amplitude: 0.15 },              // G5 (fifth) — full chord
    ],
  }),

  // MESSAGE: Bell / chime — organic with natural decay.
  // 698 Hz (F5) with overtones that decay at different rates.
  // Quick attack, long ring. Unmistakably a notification, not an alarm.
  message_tone: generateWav({
    duration: 1.4,
    attackTime: 0.02,
    releaseTime: 0.8,
    volume: 0.75,
    frequencies: [
      { freq: 698, amplitude: 1.0, decay: 1.2 },   // F5 fundamental
      { freq: 880, amplitude: 0.5, decay: 2.0 },   // A5 (third)
      { freq: 1047, amplitude: 0.3, decay: 3.0 },  // C6 (fifth)
      { freq: 1397, amplitude: 0.15, decay: 4.0 }, // F6 octave shimmer
    ],
  }),

  // THRUM: Loopable sequence for dispatch alert.
  // Pre-built pattern: 3 thrums (800ms each) + 250ms gaps + 1000ms pause = ~4.3s loop.
  // Eliminates need for procedural scheduling; plays seamlessly via notification channel.
  // Each thrum: 600ms attack (long swell) + 100ms release (crisp cutoff).
  // Frequencies: 175 Hz fundamental (deep, phone-speaker optimized) + inharmonic overtones.
  dispatch_thrum: (() => {
    const singleThrum = generateWav({
      duration: 0.8,
      attackTime: 0.6,
      releaseTime: 0.1,
      volume: 1.0,
      tremolo: { rate: 60, depth: 0.04 },
      compress: 4,
      frequencies: [
        { freq: 175, amplitude: 1.0 },
        { freq: 280, amplitude: 0.5 },
        { freq: 350, amplitude: 0.2 },
      ],
    });
    const gap = generateSilence(0.25);
    const finalPause = generateSilence(1.0);
    return concatenateWavs([singleThrum, gap, singleThrum, gap, singleThrum, gap, finalPause]);
  })(),
};

// ────────────────────────────────────────────────────────────────────────
// WRITE FILES
// ────────────────────────────────────────────────────────────────────────

const assetsDir = path.join(__dirname, 'assets', 'sounds');
const rawDir = path.join(__dirname, 'android', 'app', 'src', 'main', 'res', 'raw');

fs.mkdirSync(assetsDir, { recursive: true });
fs.mkdirSync(rawDir, { recursive: true });

for (const [name, wavBuffer] of Object.entries(tones)) {
  const assetPath = path.join(assetsDir, `${name}.wav`);
  const rawPath = path.join(rawDir, `${name}.wav`);

  fs.writeFileSync(assetPath, wavBuffer);
  fs.writeFileSync(rawPath, wavBuffer);

  const kb = (wavBuffer.length / 1024).toFixed(1);
  console.log(`✓ ${name}.wav (${kb} KB) → assets/sounds/ + res/raw/`);
}

console.log(`\nDone. ${Object.keys(tones).length} tones generated.`);
