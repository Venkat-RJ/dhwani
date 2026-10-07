# Synthetic recognition benchmark

This directory defines a corpus and evaluates isolated Talky result files.
It contains no recordings, private dictations, or measured recognition results.
The evaluator tests verify scoring and evidence validation with fixtures.
They do not establish recognition accuracy.

The Python tools use the standard library and do not start Talky, play audio, record, change permissions, or select audio devices.

## Corpus

`corpus.json`, version `1.0.0`, contains ten project-authored synthetic cases under the project's MIT license.
The people, budgets, and workshop events are fictional.
Each locale has ordinary prose, technical names, spoken punctuation, number formats, and a longer passage.
The supported reference locales are `en-US` and `en-IN`.

Each case provides exact reference text, spoken text, segment identifiers, suggested vocabulary hints, speech rate, and pause duration.
The two long cases have 694 and 696 lexical words across eight sections.
At the suggested 160 words per minute, plan for roughly 4.4 minutes plus pauses.
That estimate is a planning aid, not measured playback or capture duration.

Punctuation cases intentionally speak words such as "comma" and "question mark" while the reference uses the desired marks.
Failure to interpret those instructions is a valid result to retain.
Technical names and number formats are also stress cases, not promises about supported syntax.

Inspect and prepare a case:

```bash
python3 -I test/benchmarks/benchmark.py list
python3 -I test/benchmarks/benchmark.py prepare \
  --case en-in-long-01 --output-dir /tmp/talky-en-in-long-01
```

The destination must not already exist.
Preparation exports `reference.txt`, `say.txt`, and `metadata.template.json` into a private directory.
The `say.txt` file includes explicit macOS `say` pause instructions.
Preparation plays no audio and creates no result.
Every prepared capture gets a fresh UUID and a hash of the complete case definition.

## Recording protocol

Recording is a separate, explicitly authorized action.
Use [the isolated command interface](../../TESTING.md#command-interface-and-test-isolation), an already permitted local build, and a fresh private data directory.
For a synthetic loopback, use installed voices and the BlackHole prerequisites described in [TESTING.md](../../TESTING.md#live-loopback-test).
Record the original audio devices and restore them after the run, including failures.
The existing numbered-sentence `voice-test.sh` generates a different corpus and is not a recognition benchmark for these cases.

1. Select the reference locale in Talky and record the vocabulary hints actually used.
   Record the tested bundle's source SHA256 and full Git commit, rather than assuming the current checkout matches the running app.
2. Copy the metadata template to a run-specific metadata file.
   Fill the OS version, hardware, exact installed voice name or identifier, voice locale, generator, speech rate, and relevant environmental notes.
   Do not download a missing voice as part of the benchmark setup.
3. Record `test_requested_at` in UTC and send `test-start:<UUID>`.
   Wait for that UUID's `listening` result and verify its microphone is the intended loopback.
   A refusal, another active capture, or a missing acknowledgement is a failed run.
4. Record `audio_started_at` immediately before playing the prepared `say.txt` with the recorded voice and rate.
   Record `audio_finished_at` immediately after playback finishes.
5. Record `stop_requested_at` immediately before sending `test-stop:<UUID>`.
   Wait for the same UUID's terminal result.
   Keep failed and cancelled results alongside successful results.
6. Restore the original audio routing and verify it.
   Do not test automatic delivery while scoring recognition.

Use timezone-aware ISO 8601 timestamps, preferably with millisecond precision.
For example, a timestamp is `2026-10-07T10:00:12.345Z`.
Playback timestamps describe the playback interval observed by the harness, including configured pauses.
The result's capture duration also includes processing time.

For reproducible synthetic playback after the required permissions and routing are already arranged, the prepared prompt can be passed to `say -v '<installed voice>' -r 160 -f /tmp/talky-en-in-long-01/say.txt`.
Record the exact value used for `-v`; an `en-IN` reference alone does not establish that the synthetic voice had an Indian accent.

For real-microphone evidence, use only synthetic text or a separately consented sample.
Set `audio_source.kind` to `microphone` and provide `speaker_sample_id`, `environment`, and `consent` in the metadata.
Record speaking style, distance, microphone, noise conditions, and whether the reference was read verbatim.
Synthetic loopback and real-microphone results are separate conditions.

## Evaluate a result

```bash
python3 -I test/benchmarks/benchmark.py evaluate \
  --case en-in-long-01 \
  --result /absolute/private-data/test-results/UUID.json \
  --metadata /absolute/run-metadata.json \
  --expected-run-id UUID \
  --output /absolute/new-report.json
```

The evaluator checks the expected UUID, selected case and locale, optional case hash, terminal capture phase, freshness, microphone identity for loopback runs, and timing order.
It retains scores for failed captures, with `capture_succeeded` false.
Missing runtime metadata is listed and returns a failing exit status unless `--allow-incomplete-metadata` is explicitly supplied.
That option still leaves `runtime_metadata_complete` false.
The evaluator validates supplied provenance fields but cannot independently prove the bundle, voice, hardware, or permissions described by the caller.

Exit `0` means a terminal successful capture was evaluated with complete metadata, or incomplete metadata was explicitly allowed.
It is not a project accuracy gate.
An optional `--max-wer 0.15` applies a caller-selected limit to `locale_v1`; the project has no established quality threshold yet.
Exit `1` means a failed/cancelled capture, incomplete metadata, or an exceeded requested limit.
Exit `2` means invalid input or an output-write error.
Reports never overwrite an existing report file.

## Scores and normalization

Word error rate is `(substitutions + deletions + insertions) / reference words`.
It can exceed 100 percent when insertions exceed the reference length.
The minimum-edit alignment uses deterministic ties: substitution, then deletion, then insertion.
Both views are always reported:

- `lexical_v1`: Unicode NFKC, case folding, straightened curly apostrophes, and word tokens with internal apostrophes.
  Dotted initials such as `A.M.` become `am`.
  Punctuation and hyphens separate words and are not part of WER.
  Grouped integers and decimals remain surface tokens, so `42` differs from `forty two`.
- `locale_v1`: the same rules, plus digit integers up to 999,999,999 expanded without "and".
  `en-US` uses million and thousand; `en-IN` uses crore and lakh and accepts either valid Indian or Western comma grouping.
  Malformed grouping remains unchanged.
  The explicit spelling map merges colour/color, organise/organize, finalise/finalize, centre/center, metre/meter, normalise/normalize, and behaviour/behavior, including the listed inflections in `benchmark.py`.
  It does not add phonetic aliases for technical names, convert currencies, expand decimals or ordinals, remove spoken punctuation commands, or reinterpret number-word phrases.

The locale-normalized view can reduce surface-format penalties.
Publish the lexical score beside it so those changes remain visible.
Decimals such as `3.2` remain distinct from "three point two" in both views.
These choices are versioned evaluation rules, not repairs applied by Talky.

Punctuation is a separate edit distance over the sequence of `. , ! ? ; :` marks.
It includes decimal points and does not measure where a mark belongs relative to words, quote matching, paragraph breaks, or grammar.
Exact code, terminal commands, paths, capitalization, and executable syntax need literal-output checks.
A low WER or punctuation score cannot certify them.
Delivery success is also separate from recognition and must be tested in the destination app.

Per-segment diagnostics use the locale-normalized alignment.
`possible_missing` means at least 75 percent of a segment's words were deleted; alignment ambiguity can make that a suspicion rather than proof.
`exact_duplicate` means the entire normalized segment appears more than once in the hypothesis.
Partial or altered repetitions may appear only as insertions and require transcript review.
No numbered-sentence coverage is substituted for either word-error score.

Completion latency measures the interval from the caller's stop request to the app's final result.
Talky currently writes whole-second timestamps, so the evaluator reports lower and upper bounds using both timestamps' precision.
It does not invent a millisecond point estimate from a second-resolution result.

## Repetition and publication

Run each selected case at least three times for each distinct locale, voice, model/settings, hardware, and audio condition.
Keep individual reports, failures, references, and run metadata.
Report pooled WER using total edits divided by total reference words, rather than an unweighted average of different-length cases.
Describe completion latency with its quantization bounds and report delivery checks separately.
Do not combine synthetic voices with human recordings under one unlabeled accuracy number.

Before sharing evidence, verify that it contains only synthetic or consented content and review environmental metadata for private information.
The repository should contain the corpus, evaluator, and fixture tests.
Private run outputs belong outside Git.

Run evaluator checks without recording:

```bash
python3 -I test/benchmarks/test_benchmark.py
```
