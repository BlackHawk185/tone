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
  // DISPATCH: Rich two-tone chord with gentle rise + tremolo.
  // 440 Hz (A4) + 554 Hz (C#5) = A major third — warm, resolved, not tense.
  // Tremolo at 4 Hz gives it a living, breathing quality.
  // Assertive 3s duration — long enough to register even from sleep.
  dispatch_tone: generateWav({
    duration: 3.0,
    attackTime: 0.2,
    releaseTime: 0.7,
    volume: 0.9,
    tremolo: { rate: 4, depth: 0.25 },
    frequencies: [
      { freq: 440, bend: 494, amplitude: 1.0 },    // A4 rises to B4
      { freq: 554, bend: 587, amplitude: 0.7 },    // C#5 rises to D5
      { freq: 880, amplitude: 0.2 },                // octave overtone for brightness
      { freq: 660, bend: 700, amplitude: 0.3 },     // 5th for fullness
    ],
  }),

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

  // THRUM: Single low swell pulse for dispatch alert sequence.
  // 800ms, long fade-in (600ms attack). Played in 3 groups of 3
  // programmatically with amplitude-ramped vibration.
  // 110 Hz fundamental (A2) — as low as practical for phone speakers.
  // Missing-fundamental trick: harmonics at 220/330/440 carry energy;
  // brain perceives deep ~110 Hz.
  dispatch_thrum: generateWav({
    duration: 0.8,
    attackTime: 0.6,               // long swell — this IS the tone
    releaseTime: 0.1,              // quick cutoff — crisp end
    volume: 1.0,
    tremolo: { rate: 60, depth: 0.04 },
    compress: 4,
    frequencies: [
      { freq: 175, amplitude: 1.0 },            // single base tone — no beating
      { freq: 280, amplitude: 0.5 },             // detuned ~1.6x — inharmonic, robotic
      { freq: 350, amplitude: 0.2 },             // ~2x but sharp — metallic edge
    ],
  }),
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
