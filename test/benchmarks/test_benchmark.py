#!/usr/bin/env python3
"""Evaluator fixture tests. These are not live recognition results."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location("talky_benchmark", ROOT / "benchmark.py")
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)
RUN_ID = "12345678-1234-4234-9234-123456789ABC"


def small_case():
    return {"id": "fixture", "locale": "en-US", "category": "fixture", "segments": [
        {"id": "opening", "reference": "The first passage opens with bright morning light."},
        {"id": "middle", "reference": "The middle passage explains a careful independent experiment."},
        {"id": "ending", "reference": "The final passage closes with several useful observations."},
    ]}


def evidence(case):
    result = {"runID": RUN_ID, "phase": "completed",
              "transcript": " ".join(s["reference"] for s in case["segments"]), "error": None,
              "startedAt": "2026-10-07T10:00:00Z", "finishedAt": "2026-10-07T10:00:12Z",
              "microphone": "BlackHole 2ch"}
    metadata = {"run_id": RUN_ID, "case_id": case["id"], "case_sha256": benchmark.case_hash(case),
                "locale": case["locale"], "app_commit": "a" * 40, "source_sha256": "b" * 64,
                "macos_version": "fixture-only", "hardware": "fixture-only",
                "audio_source": {"kind": "synthetic_loopback", "generator": "fixture-only",
                                 "voice_id": "fixture-only", "speech_rate_wpm": 160},
                "settings": {"test_capture": True, "adds_punctuation": True, "vocabulary": []},
                "test_requested_at": "2026-10-07T09:59:59.900Z",
                "audio_started_at": "2026-10-07T10:00:01.000Z",
                "audio_finished_at": "2026-10-07T10:00:09.000Z",
                "stop_requested_at": "2026-10-07T10:00:10.100Z"}
    return result, metadata


class EvaluatorTests(unittest.TestCase):
    def test_known_word_edits_and_rates(self):
        score = benchmark.align(["we", "test", "the", "draft"], ["we", "check", "the", "draft", "today"])
        self.assertEqual((score["substitution"], score["deletion"], score["insertion"]), (1, 0, 1))
        self.assertEqual(score["wer"], 0.5)
        self.assertEqual(benchmark.align(["keep", "every", "word"], ["keep", "word"])["deletion"], 1)

    def test_insertions_can_make_wer_exceed_one(self):
        self.assertEqual(benchmark.align(["one"], ["one", "extra", "extra"])["wer"], 2)
        self.assertIsNone(benchmark.align([], ["extra"])["wer"])

    def test_unicode_apostrophes_and_dotted_initials(self):
        self.assertEqual(benchmark.tokens("Don't change A.M.", "en-US"),
                         benchmark.tokens("DON’T change AM", "en-US"))

    def test_regional_integer_expansion(self):
        self.assertEqual(benchmark.tokens("1,200,000", "en-US"),
                         benchmark.tokens("one million two hundred thousand", "en-US"))
        self.assertEqual(benchmark.tokens("12,00,000", "en-IN"), ["twelve", "lakh"])
        self.assertEqual(benchmark.tokens("1,200,000", "en-IN"), ["twelve", "lakh"])
        self.assertEqual(benchmark.tokens("3,00,00,000", "en-IN"), ["three", "crore"])
        self.assertEqual(benchmark.tokens("1,2", "en-US"), ["1,2"])

    def test_normalized_spelling_does_not_hide_lexical_score(self):
        self.assertEqual(benchmark.tokens("finalise colour", "en-IN"), ["finalize", "color"])
        self.assertNotEqual(benchmark.tokens("finalise colour", "en-IN", "lexical_v1"),
                            benchmark.tokens("finalize color", "en-IN", "lexical_v1"))
        self.assertEqual(benchmark.tokens("3.2", "en-US"), ["3.2"])
        self.assertEqual(benchmark.tokens("12th", "en-US"), ["12th"])

    def test_missing_middle_segment(self):
        case = small_case()
        heard = case["segments"][0]["reference"] + " " + case["segments"][2]["reference"]
        report = benchmark.score_case(case, heard)
        missing = [s["segment_id"] for s in report["segments"] if s["possible_missing"]]
        self.assertEqual(missing, ["middle"])
        self.assertEqual(report["segments"][1]["deletion_fraction"], 1)

    def test_exact_duplicate_middle_segment(self):
        case = small_case()
        heard = " ".join(case["segments"][i]["reference"] for i in (0, 1, 1, 2))
        report = benchmark.score_case(case, heard)
        duplicated = [s["segment_id"] for s in report["segments"] if s["exact_duplicate"]]
        self.assertEqual(duplicated, ["middle"])
        self.assertEqual(report["segments"][1]["exact_occurrences"], 2)
        self.assertGreater(report["scores"]["locale_v1"]["insertion"], 0)

    def test_punctuation_errors_are_separate_from_wer(self):
        case = {"id": "marks", "locale": "en-US", "category": "fixture",
                "segments": [{"id": "one", "reference": "Hello, reader."}]}
        report = benchmark.score_case(case, "Hello reader")
        self.assertEqual(report["scores"]["lexical_v1"]["wer"], 0)
        self.assertEqual(report["punctuation"]["edits"], 2)

    def test_valid_isolated_result_and_quantized_latency(self):
        case = small_case()
        result, metadata = evidence(case)
        report = benchmark.evaluate(case, result, metadata, RUN_ID)
        self.assertTrue(report["capture_succeeded"])
        self.assertTrue(report["runtime_metadata_complete"])
        self.assertAlmostEqual(report["audio_duration_seconds"], 8)
        bounds = report["completion_latency"]
        self.assertAlmostEqual(bounds["lower_bound_seconds"], 1.899, places=3)
        self.assertAlmostEqual(bounds["upper_bound_seconds"], 2.9, places=3)
        metadata["stop_requested_at"] = "2026-10-07T10:00:12.700Z"
        bounds = benchmark.evaluate(case, result, metadata, RUN_ID)["completion_latency"]
        self.assertEqual(bounds["lower_bound_seconds"], 0)
        self.assertAlmostEqual(bounds["upper_bound_seconds"], 0.3, places=3)

    def test_reject_wrong_run_case_locale_and_reference(self):
        case = small_case()
        for field, wrong in (("run_id", "87654321-4321-4321-8321-123456789ABC"),
                             ("case_id", "another-case"), ("locale", "en-IN"),
                             ("case_sha256", "c" * 64)):
            result, metadata = evidence(case)
            metadata[field] = wrong
            with self.subTest(field=field), self.assertRaises(ValueError):
                benchmark.evaluate(case, result, metadata, RUN_ID)

    def test_reject_stale_results_and_invalid_timing(self):
        case = small_case()
        for field, value in (("test_requested_at", "2026-10-07T10:00:02Z"),
                             ("audio_finished_at", "2026-10-07T10:00:15Z"),
                             ("stop_requested_at", "2026-10-07T10:00:08Z")):
            result, metadata = evidence(case)
            metadata[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                benchmark.evaluate(case, result, metadata, RUN_ID)
        with self.assertRaises(ValueError):
            benchmark.timestamp("2026-10-07T10:00:00")
        with self.assertRaises(ValueError):
            benchmark.timestamp("2026-10-07T10:00Z")

    def test_failed_capture_still_has_an_error_score(self):
        case = small_case()
        result, metadata = evidence(case)
        result.update(phase="failed", error="fixture interruption", transcript=case["segments"][0]["reference"])
        report = benchmark.evaluate(case, result, metadata, RUN_ID)
        self.assertFalse(report["capture_succeeded"])
        self.assertGreater(report["scores"]["locale_v1"]["wer"], 0)
        self.assertEqual(report["capture_error"], "fixture interruption")

    def test_incomplete_metadata_cannot_be_reported_complete(self):
        case = small_case()
        result, metadata = evidence(case)
        metadata["source_sha256"] = None
        metadata["stop_requested_at"] = None
        report = benchmark.evaluate(case, result, metadata, RUN_ID)
        self.assertFalse(report["runtime_metadata_complete"])
        self.assertEqual(report["missing_metadata"], ["source_sha256", "stop_requested_at"])
        self.assertIsNone(report["completion_latency"])

    def test_reject_wrong_microphone_and_invalid_metadata_types(self):
        case = small_case()
        result, metadata = evidence(case)
        result["microphone"] = "Built-in Microphone"
        with self.assertRaises(ValueError):
            benchmark.evaluate(case, result, metadata, RUN_ID)
        result, metadata = evidence(case)
        metadata["audio_source"] = []
        with self.assertRaises(ValueError):
            benchmark.evaluate(case, result, metadata, RUN_ID)

    def test_corpus_round_trip_and_long_passage_size(self):
        corpus = benchmark.load_corpus()
        self.assertEqual(len(corpus["cases"]), 10)
        for case in corpus["cases"]:
            with self.subTest(case=case["id"]):
                heard = " ".join(s["reference"] for s in case["segments"])
                report = benchmark.score_case(case, heard)
                self.assertEqual(report["scores"]["lexical_v1"]["wer"], 0)
                self.assertEqual(report["scores"]["locale_v1"]["wer"], 0)
                self.assertFalse(any(s["possible_missing"] or s["exact_duplicate"] for s in report["segments"]))
                if case["category"] == "long_passage":
                    self.assertGreater(report["scores"]["lexical_v1"]["reference_words"], 650)
                    self.assertEqual(len(case["segments"]), 8)

    def test_export_is_text_only_and_never_overwrites(self):
        case = benchmark.load_corpus()["cases"][0]
        with tempfile.TemporaryDirectory() as temp:
            destination = Path(temp) / "prepared"
            run_id = benchmark.prepare(case, destination)
            self.assertEqual({p.name for p in destination.iterdir()},
                             {"reference.txt", "say.txt", "metadata.template.json"})
            metadata = json.loads((destination / "metadata.template.json").read_text())
            self.assertEqual(metadata["run_id"], run_id)
            self.assertIsNone(metadata["stop_requested_at"])
            self.assertIn("[[slnc 600]]", (destination / "say.txt").read_text())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            self.assertEqual((destination / "metadata.template.json").stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                benchmark.prepare(case, destination)

    def test_cli_reports_failed_capture_and_preserves_evidence(self):
        case = benchmark.load_corpus()["cases"][0]
        result, metadata = evidence(case)
        result.update(phase="failed", error="fixture interruption")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "result.json").write_text(json.dumps(result))
            (root / "metadata.json").write_text(json.dumps(metadata))
            report_path = root / "report.json"
            command = [sys.executable, "-I", str(ROOT / "benchmark.py"), "evaluate", "--case", case["id"],
                       "--result", str(root / "result.json"), "--metadata", str(root / "metadata.json"),
                       "--expected-run-id", RUN_ID, "--output", str(report_path)]
            process = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(process.returncode, 1, process.stderr)
            self.assertEqual(json.loads(report_path.read_text())["capture_phase"], "failed")
            self.assertEqual(report_path.stat().st_mode & 0o777, 0o600)
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(second.returncode, 2)
            self.assertIn("exists", second.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
