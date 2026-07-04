#!/usr/bin/env python3
"""Generate small piano MIDI ideas from compact natural-language prompts."""

from __future__ import annotations

import argparse
import random
import re
import struct
import sys
import time
from dataclasses import dataclass
from pathlib import Path

TPQ = 480

NOTE_NAMES = {
    "C": 0,
    "C#": 1,
    "DB": 1,
    "D": 2,
    "D#": 3,
    "EB": 3,
    "E": 4,
    "F": 5,
    "F#": 6,
    "GB": 6,
    "G": 7,
    "G#": 8,
    "AB": 8,
    "A": 9,
    "A#": 10,
    "BB": 10,
    "B": 11,
}

KEY_ALIASES = {
    "c": "C",
    "db": "Db",
    "d♭": "Db",
    "d": "D",
    "eb": "Eb",
    "e♭": "Eb",
    "e": "E",
    "f": "F",
    "gb": "Gb",
    "g♭": "Gb",
    "g": "G",
    "ab": "Ab",
    "a♭": "Ab",
    "a": "A",
    "bb": "Bb",
    "b♭": "Bb",
    "b": "B",
}

PROGRESSIONS = {
    "neo_soul": [
        ("Db", "maj9"),
        ("C", "m11"),
        ("F", "13sus"),
        ("Bb", "m9"),
    ],
    "gospel": [
        ("F", "m9"),
        ("Bb", "13sus"),
        ("Eb", "maj9"),
        ("Ab", "maj9"),
    ],
    "minor": [
        ("A", "m9"),
        ("D", "m11"),
        ("G", "13sus"),
        ("C", "maj9"),
    ],
    "lofi": [
        ("Eb", "maj9"),
        ("D", "m9"),
        ("G", "13sus"),
        ("C", "m11"),
    ],
}


@dataclass(frozen=True)
class Instrument:
    slug: str
    display_name: str
    program: int
    tags: tuple[str, ...]


PIANO_KEYBOARD_INSTRUMENTS = [
    Instrument("studio-grand", "Studio Grand Piano", 0, ("grand", "acoustic", "classic")),
    Instrument("bright-piano", "Bright Piano", 1, ("bright", "pop", "cutting")),
    Instrument("electric-grand", "Electric Grand Piano", 2, ("electric", "grand", "fusion")),
    Instrument("honky-tonk", "Honky Tonk Piano", 3, ("lofi", "vintage", "detuned")),
    Instrument("warm-ep", "Warm Electric Piano", 4, ("electric", "rhodes", "warm", "neo-soul")),
    Instrument("digital-ep", "Digital Electric Piano", 5, ("electric", "dx", "bell", "glassy")),
    Instrument("harpsichord", "Harpsichord", 6, ("baroque", "pluck", "cinematic")),
    Instrument("clavinet", "Clavinet", 7, ("clav", "funk", "percussive")),
]

DEFAULT_AUTO_INSTRUMENTS = ("warm-ep", "electric-grand", "studio-grand", "digital-ep", "bright-piano", "clavinet")


@dataclass(frozen=True)
class NoteEvent:
    start: int
    duration: int
    note: int
    velocity: int
    channel: int = 0


def varlen(value: int) -> bytes:
    buffer = value & 0x7F
    value >>= 7
    encoded = bytearray()
    while value:
        encoded.insert(0, 0x80 | buffer)
        buffer = value & 0x7F
        value >>= 7
    encoded.append(buffer)
    return bytes(encoded)


def midi_note(name: str, octave: int) -> int:
    key = name.upper().replace("♭", "B")
    if key not in NOTE_NAMES:
        raise ValueError(f"Unsupported note name: {name}")
    return (octave + 1) * 12 + NOTE_NAMES[key]


def chord_intervals(quality: str) -> list[int]:
    qualities = {
        "maj9": [0, 4, 7, 11, 14],
        "m9": [0, 3, 7, 10, 14],
        "m11": [0, 3, 7, 10, 14, 17],
        "13sus": [0, 5, 7, 10, 14, 21],
        "7alt": [0, 4, 10, 13, 15, 20],
    }
    return qualities.get(quality, qualities["maj9"])


def parse_bars(prompt: str, fallback: int) -> int:
    patterns = [
        r"(\d+)\s*마디",
        r"(\d+)\s*bar",
        r"(\d+)\s*bars",
        r"(\d+)\s*measure",
        r"(\d+)\s*measures",
    ]
    for pattern in patterns:
        match = re.search(pattern, prompt, flags=re.IGNORECASE)
        if match:
            return max(1, min(32, int(match.group(1))))
    return fallback


def parse_tempo(prompt: str, fallback: int) -> int:
    match = re.search(r"(\d{2,3})\s*(?:bpm|템포)", prompt, flags=re.IGNORECASE)
    if match:
        return max(40, min(220, int(match.group(1))))
    return fallback


def parse_key(prompt: str, fallback: str) -> str:
    match = re.search(r"\b([A-Ga-g](?:#|b|♭)?)\s*(?:major|minor|maj|min|키|key)\b", prompt)
    if match:
        return KEY_ALIASES.get(match.group(1).lower(), fallback)
    return fallback


def choose_palette(prompt: str) -> str:
    lower = prompt.lower()
    if any(word in lower for word in ["gospel", "가스펠", "교회"]):
        return "gospel"
    if any(word in lower for word in ["minor", "마이너", "dark", "어둡"]):
        return "minor"
    if any(word in lower for word in ["lofi", "lo-fi", "로파이"]):
        return "lofi"
    return "neo_soul"


def normalize_instrument_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def instruments_by_slug(slugs: tuple[str, ...] | set[str]) -> list[Instrument]:
    by_slug = {instrument.slug: instrument for instrument in PIANO_KEYBOARD_INSTRUMENTS}
    if isinstance(slugs, tuple):
        return [by_slug[slug] for slug in slugs]
    return [instrument for instrument in PIANO_KEYBOARD_INSTRUMENTS if instrument.slug in slugs]


def instrument_candidates(prompt: str) -> list[Instrument]:
    lower = prompt.lower()

    if any(word in lower for word in ["clav", "클라비", "funk", "펑크"]):
        return instruments_by_slug({"clavinet"})

    if any(word in lower for word in ["rhodes", "ep", "electric", "일렉", "전기", "neo", "네오"]):
        return instruments_by_slug({"warm-ep", "electric-grand", "digital-ep"})

    if any(word in lower for word in ["lofi", "lo-fi", "로파이", "빈티지", "detune"]):
        return instruments_by_slug({"honky-tonk", "warm-ep", "electric-grand"})

    if any(word in lower for word in ["bright", "밝", "pop", "팝"]):
        return instruments_by_slug({"bright-piano", "studio-grand", "digital-ep"})

    if any(word in lower for word in ["grand", "그랜드", "acoustic", "어쿠스틱"]):
        return instruments_by_slug({"studio-grand", "bright-piano"})

    return instruments_by_slug(DEFAULT_AUTO_INSTRUMENTS)


def choose_instrument(prompt: str, rng: random.Random, requested: str) -> Instrument:
    requested_slug = normalize_instrument_name(requested)
    if requested_slug and requested_slug != "auto":
        for instrument in PIANO_KEYBOARD_INSTRUMENTS:
            names = {instrument.slug, normalize_instrument_name(instrument.display_name), *instrument.tags}
            if requested_slug in names:
                return instrument
        valid = ", ".join(instrument.slug for instrument in PIANO_KEYBOARD_INSTRUMENTS)
        raise ValueError(f"Unknown instrument '{requested}'. Use one of: auto, {valid}")

    candidates = instrument_candidates(prompt)
    return rng.choice(candidates)


def suggest_instruments(prompt: str) -> list[Instrument]:
    candidates = instrument_candidates(prompt)
    if len(candidates) <= 3:
        return candidates
    return candidates[:3]


def transpose_progression(progression: list[tuple[str, str]], target_key: str) -> list[tuple[str, str]]:
    if target_key == "Db":
        return progression

    source = NOTE_NAMES["DB"]
    target = NOTE_NAMES[target_key.upper().replace("♭", "B")]
    shift = target - source

    reverse = {
        0: "C",
        1: "Db",
        2: "D",
        3: "Eb",
        4: "E",
        5: "F",
        6: "Gb",
        7: "G",
        8: "Ab",
        9: "A",
        10: "Bb",
        11: "B",
    }

    transposed = []
    for root, quality in progression:
        value = (NOTE_NAMES[root.upper().replace("♭", "B")] + shift) % 12
        transposed.append((reverse[value], quality))
    return transposed


def human_ticks(rng: random.Random, amount: int = 18) -> int:
    return rng.randint(-amount, amount)


def make_voicing(root: str, quality: str, rng: random.Random) -> tuple[list[int], list[int]]:
    root_low = midi_note(root, 2)
    root_mid = midi_note(root, 3)
    intervals = chord_intervals(quality)

    left = [root_low, root_low + 7]
    if quality in {"m9", "m11"}:
        left = [root_low, root_low + 10]
    elif quality == "13sus":
        left = [root_low, root_low + 10]

    right = [root_mid + interval for interval in intervals[1:]]
    while min(right) < 55:
        right = [note + 12 for note in right]
    while max(right) > 82:
        right = [note - 12 for note in right]

    if rng.random() < 0.45:
        right = right[1:] + [right[0] + 12]
    return left, sorted(right)


def generate_events(prompt: str, bars: int, tempo: int, key: str, seed: int) -> list[NoteEvent]:
    rng = random.Random(seed)
    palette = choose_palette(prompt)
    progression = transpose_progression(PROGRESSIONS[palette], key)
    events: list[NoteEvent] = []

    bar_ticks = TPQ * 4
    for bar in range(bars):
        root, quality = progression[bar % len(progression)]
        left, right = make_voicing(root, quality, rng)
        bar_start = bar * bar_ticks

        push = human_ticks(rng)
        chord_duration = int(TPQ * rng.choice([2.75, 3.0, 3.25]))
        velocity = rng.randint(64, 82)

        for note in left:
            events.append(NoteEvent(bar_start + max(0, push), chord_duration, note, velocity - 8))

        for index, note in enumerate(right):
            start = bar_start + max(0, push + index * rng.randint(5, 16))
            events.append(NoteEvent(start, chord_duration - index * 10, note, velocity + rng.randint(-5, 7)))

        # Add small upper-neighbor color notes for a played, not block-programmed, feel.
        if rng.random() < 0.8:
            color_start = bar_start + TPQ * rng.choice([2, 3]) + rng.randint(-30, 30)
            color_notes = rng.sample(right[-3:], k=min(2, len(right[-3:])))
            for note in color_notes:
                events.append(NoteEvent(max(0, color_start), int(TPQ * 0.55), note + rng.choice([2, 3, 5]), rng.randint(45, 62)))

        if rng.random() < 0.55:
            pickup_start = bar_start + int(TPQ * 3.45) + rng.randint(-20, 20)
            events.append(NoteEvent(max(0, pickup_start), int(TPQ * 0.35), right[-1] - 2, rng.randint(42, 58)))

    return sorted(events, key=lambda event: (event.start, event.note))


def meta_text(event_type: int, text: str) -> bytes:
    payload = text.encode("utf-8")
    return b"\xff" + bytes([event_type]) + varlen(len(payload)) + payload


def make_track(events: list[NoteEvent], tempo: int, instrument: Instrument) -> bytes:
    raw = bytearray()
    microseconds_per_quarter = int(60_000_000 / tempo)
    raw.extend(varlen(0) + meta_text(0x03, instrument.display_name))
    raw.extend(varlen(0) + b"\xff\x51\x03" + microseconds_per_quarter.to_bytes(3, "big"))
    raw.extend(varlen(0) + b"\xff\x58\x04\x04\x02\x18\x08")
    raw.extend(varlen(0) + bytes([0xC0, instrument.program]))

    timed_messages: list[tuple[int, int, bytes]] = []
    for event in events:
        start = max(0, event.start)
        end = max(start + 1, start + event.duration)
        timed_messages.append((start, 0, bytes([0x90 | event.channel, event.note, event.velocity])))
        timed_messages.append((end, 1, bytes([0x80 | event.channel, event.note, 0])))

    current = 0
    for tick, _, message in sorted(timed_messages, key=lambda item: (item[0], item[1])):
        raw.extend(varlen(tick - current))
        raw.extend(message)
        current = tick

    raw.extend(varlen(0) + b"\xff\x2f\x00")
    return b"MTrk" + struct.pack(">I", len(raw)) + bytes(raw)


def write_midi(path: Path, events: list[NoteEvent], tempo: int, instrument: Instrument) -> None:
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, TPQ)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + make_track(events, tempo, instrument))


def default_output(prompt: str) -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    slug = re.sub(r"[^a-z0-9가-힣]+", "-", prompt.lower()).strip("-")[:48]
    if not slug:
        slug = "idea"
    return Path("generated") / f"{stamp}-{slug}.mid"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate a short piano MIDI idea.")
    parser.add_argument("prompt", help="Natural-language music request.")
    parser.add_argument("--bars", type=int, default=4, help="Number of bars when not stated in prompt.")
    parser.add_argument("--tempo", type=int, default=86, help="Tempo in BPM when not stated in prompt.")
    parser.add_argument("--key", default="Db", help="Target key when not stated in prompt.")
    parser.add_argument("--instrument", default="auto", help="Piano/keyboard instrument slug, or auto.")
    parser.add_argument("--seed", type=int, help="Deterministic random seed.")
    parser.add_argument("--output", "-o", type=Path, help="Output .mid path.")
    parser.add_argument("--print-default-path", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--suggest-instruments", action="store_true", help="Print likely piano/keyboard choices for the prompt.")
    args = parser.parse_args(argv)

    if args.print_default_path:
        print(default_output(args.prompt))
        return 0

    if args.suggest_instruments:
        for instrument in suggest_instruments(args.prompt):
            print(f"{instrument.slug}\t{instrument.display_name}\tprogram={instrument.program}")
        return 0

    bars = parse_bars(args.prompt, args.bars)
    tempo = parse_tempo(args.prompt, args.tempo)
    key = parse_key(args.prompt, args.key)
    seed = args.seed if args.seed is not None else random.SystemRandom().randint(0, 2**31 - 1)
    rng = random.Random(seed)
    instrument = choose_instrument(args.prompt, rng, args.instrument)
    output = args.output or default_output(args.prompt)

    events = generate_events(args.prompt, bars=bars, tempo=tempo, key=key, seed=seed)
    write_midi(output, events, tempo, instrument)

    print(f"output={output}")
    print(f"bars={bars}")
    print(f"tempo={tempo}")
    print(f"key={key}")
    print(f"seed={seed}")
    print(f"instrument={instrument.slug}")
    print(f"instrument_name={instrument.display_name}")
    print(f"program={instrument.program}")
    print(f"events={len(events)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
