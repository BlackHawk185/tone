# Tone — Copilot Workspace Instructions

## What We're Building

**Tone** is a real-time first responder dispatch app for a small fire/EMS department (Pine Bluffs, WY).
When a tone drops, an email from the IAR (I Am Responding) dispatch system is parsed by a Cloud Run
service and written to Firestore. The Flutter app receives it instantly via live stream, shows
responders the incident details, lets them mark responding, and shares live location/ETA back to the
team — all before anyone has had a chance to think twice.

**Stack:**
- Flutter (iOS + Android primary, web secondary) — `app/`
- Firebase Firestore (real-time data), Firebase Auth — backend
- Cloud Run (Node.js) — parses IAR "Rip & Run" dispatch emails → Firestore — `cloud-run/`
- Firebase Functions (Node.js) — supporting triggers — `functions/`

## Why This Matters

This is **critical infrastructure**. Delays in response cost lives. Every second of friction — an
extra tap, a confusing screen, a missing detail — has a real cost in the field. Responders are often
driving, stressed, and acting on adrenaline. The app must be fast, clear, and reliable above all else.

**"Good enough" is not good enough here.**

## Expectations for Copilot

- **Push back.** If a proposed approach has a better alternative, say so clearly with reasoning.
- **Explore thoroughly.** Don't take the first obvious path. Consider edge cases, failure modes,
  and whether a different architecture would serve responders better.
- **Challenge assumptions.** If a UX decision might cost time or cause confusion in the field,
  raise it even if it wasn't asked about.
- **Prioritize response-time reduction** in every UI/UX decision. The primary users are in motion,
  under stress, and every interaction should require the minimum possible cognitive load.
- **Never leave known gaps unmentioned.** If a change has a limitation (e.g. Apple Maps can't
  skip the route preview), state it clearly so informed decisions can be made.
