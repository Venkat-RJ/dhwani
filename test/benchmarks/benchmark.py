#!/usr/bin/env python3
"""Prepare synthetic text and evaluate isolated Talky results. Never controls audio."""

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import re
import sys
import unicodedata
import uuid
from pathlib import Path

CORPUS_PATH = Path(__file__).with_name("corpus.json")
MAX_TOKENS = 4000
SMALL = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "zero ten twenty thirty forty fifty sixty seventy eighty ninety".split()
REGIONAL = {
    "colour": "color", "colours": "colors", "organise": "organize",
    "organised": "organized", "organising": "organizing", "finalise": "finalize",
    "finalised": "finalized", "finalising": "finalizing", "centre": "center",
    "centres": "centers", "metre": "meter", "metres": "meters",
    "normalise": "normalize", "normalised": "normalized", "normalising": "normalizing",
    "behaviour": "behavior", "behaviours": "behaviors",
}
TOKEN = re.compile(r"(?:[a-z]\.){2,}|\d+(?:,\d+)*(?:\.\d+)?(?![^\W_])|[^\W_]+(?:'[^\W_]+)*", re.UNICODE)


def load_corpus(path=CORPUS_PATH):
    corpus = json.loads(Path(path).read_text(encoding="utf-8"))
    if corpus.get("schema_version") != 1:
        raise ValueError("Unsupported corpus schema")
    cases = corpus.get("cases", [])
    identifiers = set()
    for case in cases:
        identifier = case["id"]
        if identifier in identifiers or case["locale"] not in ("en-US", "en-IN"):
            raise ValueError("Duplicate case or unsupported locale")
        identifiers.add(identifier)
        segment_ids = [segment["id"] for segment in case["segments"]]
        if not segment_ids or len(set(segment_ids)) != len(segment_ids):
            raise ValueError("Cases need unique, nonempty segments")
        if any(not tokens(segment["reference"], case["locale"], "lexical_v1") for segment in case["segments"]):
            raise ValueError("Reference segments must contain words")
    return corpus


def integer_words(value, locale):
    if value < 20:
        return [SMALL[value]]
    if value < 100:
        return [TENS[value // 10]] + (integer_words(value % 10, locale) if value % 10 else [])
    scales = [(10_000_000, "crore"), (100_000, "lakh"), (1000, "thousand"), (100, "hundred")]
    if locale == "en-US":
        scales = [(1_000_000, "million"), (1000, "thousand"), (100, "hundred")]
    for scale, word in scales:
        if value >= scale:
            return integer_words(value // scale, locale) + [word] + (integer_words(value % scale, locale) if value % scale else [])
    raise ValueError("Unsupported integer")


def tokens(text, locale, profile="locale_v1"):
    if locale not in ("en-US", "en-IN") or profile not in ("lexical_v1", "locale_v1"):
        raise ValueError("Unsupported locale or normalization profile")
    text = unicodedata.normalize("NFKC", text).casefold().replace("\u2019", "'").replace("\u2018", "'")
    result = []
    for token in TOKEN.findall(text):
        if re.fullmatch(r"(?:[a-z]\.){2,}", token):
            token = token.replace(".", "")
        if profile == "locale_v1":
            token = REGIONAL.get(token, token)
            grouped = re.fullmatch(r"\d{1,3}(?:,\d{3})+", token)
            if locale == "en-IN":
                grouped = grouped or re.fullmatch(r"\d{1,2}(?:,\d{2})*,\d{3}", token)
            if token.isascii() and (token.isdigit() or grouped):
                value = int(token.replace(",", ""))
                if value <= 999_999_999:
                    result.extend(integer_words(value, locale))
                    continue
        result.append(token)
    if len(result) > MAX_TOKENS:
        raise ValueError(f"Input exceeds {MAX_TOKENS} normalized tokens")
    return result


def align(reference, hypothesis):
    """Minimum Levenshtein alignment. Ties prefer substitution, deletion, insertion."""
    n, m = len(reference), len(hypothesis)
    trace = [bytearray(m + 1) for _ in range(n + 1)]
    for j in range(1, m + 1):
        trace[0][j] = 3
    previous = list(range(m + 1))
    for i in range(1, n + 1):
        row = [i] + [0] * m
        trace[i][0] = 2
        for j in range(1, m + 1):
            if reference[i - 1] == hypothesis[j - 1]:
                row[j], trace[i][j] = previous[j - 1], 0
            else:
                choices = (previous[j - 1] + 1, previous[j] + 1, row[j - 1] + 1)
                code = min(range(3), key=choices.__getitem__)
                row[j], trace[i][j] = choices[code], code + 1
        previous = row
    operations = []
    i, j = n, m
    while i or j:
        code = trace[i][j]
        operations.append({
            "op": ("match", "substitution", "deletion", "insertion")[code],
            "reference_index": i - 1 if code != 3 else None,
            "hypothesis_index": j - 1 if code != 2 else None,
            "reference": reference[i - 1] if code != 3 else None,
            "hypothesis": hypothesis[j - 1] if code != 2 else None,
        })
        if code != 3:
            i -= 1
        if code != 2:
            j -= 1
    operations.reverse()
    counts = {name: sum(op["op"] == name for op in operations)
              for name in ("match", "substitution", "deletion", "insertion")}
    edits = counts["substitution"] + counts["deletion"] + counts["insertion"]
    return {"reference_words": n, "hypothesis_words": m, **counts,
            "edits": edits, "wer": edits / n if n else None, "alignment": operations}


def score_case(case, hypothesis):
    scores = {}
    diagnostics = []
    for profile in ("lexical_v1", "locale_v1"):
        reference = []
        spans = []
        for segment in case["segments"]:
            words = tokens(segment["reference"], case["locale"], profile)
            spans.append((segment, len(reference), len(reference) + len(words), words))
            reference.extend(words)
        if len(reference) > MAX_TOKENS:
            raise ValueError("Reference exceeds token limit")
        heard = tokens(hypothesis, case["locale"], profile)
        score = align(reference, heard)
        operations = score.pop("alignment")
        score["word_errors"] = [op for op in operations if op["op"] != "match"]
        scores[profile] = score
        if profile == "locale_v1":
            for segment, start, end, words in spans:
                relevant = [op for op in operations if op["reference_index"] is not None
                            and start <= op["reference_index"] < end]
                deleted = sum(op["op"] == "deletion" for op in relevant)
                matched = sum(op["op"] == "match" for op in relevant)
                occurrences = [index for index in range(len(heard) - len(words) + 1)
                               if heard[index:index + len(words)] == words]
                diagnostics.append({
                    "segment_id": segment["id"], "reference_words": len(words),
                    "matched_words": matched, "deleted_words": deleted,
                    "deletion_fraction": deleted / len(words),
                    "possible_missing": deleted / len(words) >= 0.75,
                    "exact_occurrences": len(occurrences),
                    "exact_duplicate": len(occurrences) > 1,
                    "occurrence_token_offsets": occurrences,
                })
    punctuation_reference = re.findall(r"[.,!?;:]", "\n\n".join(s["reference"] for s in case["segments"]))
    punctuation_hypothesis = re.findall(r"[.,!?;:]", hypothesis)
    punctuation = align(punctuation_reference, punctuation_hypothesis)
    punctuation.pop("alignment")
    punctuation["error_rate"] = punctuation.pop("wer")
    punctuation["reference_marks"] = punctuation.pop("reference_words")
    punctuation["hypothesis_marks"] = punctuation.pop("hypothesis_words")
    return {"case_id": case["id"], "case_sha256": case_hash(case), "locale": case["locale"], "category": case["category"],
            "scores": scores, "segments": diagnostics, "punctuation": punctuation}


def case_hash(case):
    return hashlib.sha256(json.dumps(case, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("Timestamp must be an ISO 8601 string with a timezone")
    clock = re.search(r"T\d{2}:\d{2}:\d{2}(?:[.,]([0-9]+))?", value)
    if clock is None:
        raise ValueError("Timestamp must include hours, minutes, and seconds")
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Timestamp needs a timezone")
    resolution = 10 ** -len(clock.group(1)) if clock.group(1) else 1.0
    return parsed.timestamp(), resolution


def evaluate(case, result, metadata, expected_run_id):
    if not isinstance(result, dict) or not isinstance(metadata, dict):
        raise ValueError("Result and metadata must be JSON objects")
    expected = str(uuid.UUID(expected_run_id))
    if str(uuid.UUID(result["runID"])) != expected or str(uuid.UUID(metadata["run_id"])) != expected:
        raise ValueError("Result or metadata belongs to another run")
    if metadata["case_id"] != case["id"] or metadata["locale"] != case["locale"]:
        raise ValueError("Metadata case or locale does not match the selected reference")
    if metadata.get("case_sha256") is not None and metadata["case_sha256"] != case_hash(case):
        raise ValueError("Metadata refers to a different version of this case")
    if result["phase"] not in ("completed", "failed", "cancelled"):
        raise ValueError("A terminal Talky result is required")
    if not isinstance(result["transcript"], str) or not isinstance(result.get("microphone"), str):
        raise ValueError("Result needs transcript and microphone strings")
    if result.get("error") is not None and not isinstance(result["error"], str):
        raise ValueError("Capture error must be a string or null")
    started, start_resolution = timestamp(result["startedAt"])
    finished, finish_resolution = timestamp(result["finishedAt"])
    if finished < started:
        raise ValueError("Result completion precedes capture start")
    report = score_case(case, result["transcript"])
    missing = []
    for name in ("app_commit", "source_sha256", "macos_version", "hardware", "audio_source", "settings",
                 "test_requested_at", "audio_started_at", "audio_finished_at", "stop_requested_at"):
        if metadata.get(name) is None or metadata.get(name) == "":
            missing.append(name)
    if metadata.get("app_commit") is not None and not re.fullmatch(r"[0-9a-fA-F]{40}", metadata["app_commit"]):
        raise ValueError("app_commit must be the full Git SHA of the tested app")
    if metadata.get("source_sha256") is not None and not re.fullmatch(r"[0-9a-fA-F]{64}", metadata["source_sha256"]):
        raise ValueError("source_sha256 must be the tested app's full source hash")
    source = metadata.get("audio_source")
    if source is not None:
        if not isinstance(source, dict):
            raise ValueError("audio_source must be a JSON object")
        if source.get("kind") not in ("synthetic_loopback", "microphone"):
            raise ValueError("Unknown audio source kind")
        if source["kind"] == "synthetic_loopback":
            for key in ("generator", "voice_id", "speech_rate_wpm"):
                if source.get(key) is None or source.get(key) == "":
                    missing.append("audio_source." + key)
            rate = source.get("speech_rate_wpm")
            if rate is not None and (isinstance(rate, bool) or not isinstance(rate, (float, int))
                                     or not math.isfinite(rate) or rate <= 0):
                raise ValueError("Speech rate must be a positive finite number")
            if "blackhole" not in result["microphone"].lower():
                raise ValueError("Synthetic-loopback result does not identify BlackHole")
        else:
            for key in ("speaker_sample_id", "environment", "consent"):
                if not source.get(key):
                    missing.append("audio_source." + key)
    settings = metadata.get("settings")
    if settings is not None:
        if not isinstance(settings, dict) or settings.get("test_capture") is not True:
            raise ValueError("Settings must identify an isolated test capture")
        if not isinstance(settings.get("adds_punctuation"), bool):
            missing.append("settings.adds_punctuation")
        vocabulary = settings.get("vocabulary")
        if not isinstance(vocabulary, list) or any(not isinstance(word, str) for word in vocabulary):
            missing.append("settings.vocabulary")
    requested = metadata.get("test_requested_at")
    if requested is not None and started + start_resolution <= timestamp(requested)[0]:
        raise ValueError("Capture result predates the requested test")
    audio_duration = None
    if metadata.get("audio_started_at") is not None and metadata.get("audio_finished_at") is not None:
        audio_start, audio_start_resolution = timestamp(metadata["audio_started_at"])
        audio_finish, _ = timestamp(metadata["audio_finished_at"])
        if audio_finish < audio_start or audio_start + audio_start_resolution <= started or audio_finish >= finished + finish_resolution:
            raise ValueError("Audio playback timestamps fall outside the capture")
        audio_duration = audio_finish - audio_start
    latency = None
    stop = metadata.get("stop_requested_at")
    if stop is not None:
        stop_time, stop_resolution = timestamp(stop)
        if stop_time + stop_resolution <= started or stop_time >= finished + finish_resolution:
            raise ValueError("Stop request falls outside the capture")
        if metadata.get("audio_finished_at") is not None and stop_time + stop_resolution <= timestamp(metadata["audio_finished_at"])[0]:
            raise ValueError("Stop request precedes the end of playback")
        delta = finished - stop_time
        latency = {"lower_bound_seconds": max(0, delta - stop_resolution),
                   "upper_bound_seconds": max(0, delta + finish_resolution),
                   "timestamp_resolution_seconds": finish_resolution}
    report.update({
        "report_schema_version": 1, "run_id": expected,
        "capture_phase": result["phase"], "capture_error": result.get("error"),
        "capture_succeeded": result["phase"] == "completed" and not result.get("error") and bool(result["transcript"].strip()),
        "capture_wall_duration_seconds": finished - started,
        "audio_duration_seconds": audio_duration,
        "completion_latency": latency,
        "runtime_metadata_complete": not missing,
        "missing_metadata": missing,
        "reported_metadata": metadata,
    })
    return report


def prepare(case, output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    reference = "\n\n".join(segment["reference"] for segment in case["segments"])
    spoken = "\n".join(segment["spoken"] + f" [[slnc {segment['pause_after_ms']}]]"
                       for segment in case["segments"])
    metadata = {
        "run_id": str(uuid.uuid4()).upper(), "case_id": case["id"], "case_sha256": case_hash(case), "locale": case["locale"],
        "app_commit": None, "source_sha256": None, "macos_version": None, "hardware": None,
        "audio_source": {"kind": "synthetic_loopback", "generator": "macOS say",
                         "voice_id": None, "speech_rate_wpm": case["suggested_speech_rate_wpm"]},
        "settings": {"adds_punctuation": True, "vocabulary": case["vocabulary"],
                     "test_capture": True},
        "test_requested_at": None, "audio_started_at": None, "audio_finished_at": None,
        "stop_requested_at": None,
    }
    for name, content in (("reference.txt", reference + "\n"), ("say.txt", spoken + "\n"),
                          ("metadata.template.json", json.dumps(metadata, indent=2) + "\n")):
        path = output / name
        path.write_text(content, encoding="utf-8")
        path.chmod(0o600)
    return metadata["run_id"]


def read_json(path):
    path = Path(path)
    if path.stat().st_size > 1_048_576:
        raise ValueError("Input JSON exceeds one MiB")
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="List synthetic corpus cases")
    export = sub.add_parser("prepare", help="Export prompts and a metadata template; does not run audio")
    export.add_argument("--case", required=True)
    export.add_argument("--output-dir", required=True)
    score = sub.add_parser("evaluate", help="Score a terminal isolated Talky result")
    score.add_argument("--case", required=True)
    score.add_argument("--result", required=True)
    score.add_argument("--metadata", required=True)
    score.add_argument("--expected-run-id", required=True)
    score.add_argument("--output")
    score.add_argument("--max-wer", type=float, help="Optional locale_v1 WER limit; no project accuracy threshold is implied")
    score.add_argument("--allow-incomplete-metadata", action="store_true")
    args = parser.parse_args(argv)
    try:
        corpus = load_corpus()
        if args.command == "list":
            for case in corpus["cases"]:
                count = sum(len(tokens(s["reference"], case["locale"], "lexical_v1")) for s in case["segments"])
                print(f"{case['id']}: {case['locale']}, {case['category']}, {count} words, {len(case['segments'])} segments")
            return 0
        case = next((case for case in corpus["cases"] if case["id"] == args.case), None)
        if case is None:
            raise ValueError("Unknown corpus case")
        if args.command == "prepare":
            run_id = prepare(case, args.output_dir)
            print(f"Prepared {args.case} in {args.output_dir}. Run UUID: {run_id}. No audio was played or recorded.")
            return 0
        if args.max_wer is not None and (not math.isfinite(args.max_wer) or args.max_wer < 0):
            raise ValueError("WER limit must be finite and nonnegative")
        report = evaluate(case, read_json(args.result), read_json(args.metadata), args.expected_run_id)
        report["corpus_version"] = corpus["version"]
        if args.output:
            path = Path(args.output)
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(report, handle, indent=2)
                handle.write("\n")
        for profile, values in report["scores"].items():
            print(f"{profile}: WER {values['wer']:.2%}; S={values['substitution']} D={values['deletion']} I={values['insertion']}; reference={values['reference_words']} words")
        print("Possible missing segments:", ", ".join(s["segment_id"] for s in report["segments"] if s["possible_missing"]) or "none")
        print("Exact duplicated segments:", ", ".join(s["segment_id"] for s in report["segments"] if s["exact_duplicate"]) or "none")
        print(f"Capture phase: {report['capture_phase']}; complete metadata: {report['runtime_metadata_complete']}")
        if report["completion_latency"]:
            bounds = report["completion_latency"]
            print(f"Stop-to-final latency: {bounds['lower_bound_seconds']:.3f} to {bounds['upper_bound_seconds']:.3f} seconds")
        if report["missing_metadata"]:
            print("Missing metadata:", ", ".join(report["missing_metadata"]))
        accepted = report["capture_succeeded"] and (report["runtime_metadata_complete"] or args.allow_incomplete_metadata)
        accepted = accepted and (args.max_wer is None or report["scores"]["locale_v1"]["wer"] <= args.max_wer)
        return 0 if accepted else 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
