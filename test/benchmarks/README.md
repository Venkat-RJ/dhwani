# Synthetic recognition benchmark

Use these tools to prepare a synthetic test case and score its isolated Dhwani result file.
This directory contains the corpus, evaluator, and fixture tests.
It contains no recordings, private dictations, or measured recognition results.

The fixture tests check scoring and evidence validation.
They do not measure Dhwani's recognition accuracy.

The Python tools use only the standard library.
They do not start Dhwani, play or record audio, change permissions, or select audio devices.

## Corpus

`corpus.json`, version `1.0.0`, contains ten synthetic cases written for this project and covered by its MIT license.
The people, budgets, and workshop events are fictional.

The reference locales are `en-US` and `en-IN`.
Each has cases for ordinary prose, technical names, spoken punctuation, number formats, and a longer passage.

Each case provides exact reference text, spoken text, segment identifiers, suggested vocabulary hints, speech rate, and pause duration.
The two long cases have 694 and 696 lexical words across eight sections.
At the suggested 160 words per minute, plan for roughly 4.4 minutes plus pauses.
Use that estimate to plan a run. Actual playback and capture duration must be measured.

Punctuation cases intentionally speak words such as "comma" and "question mark" while the reference uses the desired marks.
Keep results where those instructions are not interpreted correctly.
Technical names and number formats also test difficult inputs; the corpus does not promise that Dhwani supports their exact syntax.

Inspect and prepare a case:

```bash
python3 -I test/benchmarks/benchmark.py list
python3 -I test/benchmarks/benchmark.py prepare \
  --case en-in-long-01 --output-dir /tmp/talky-en-in-long-01
```

The destination must not already exist.
Preparation writes three files into a private directory:

- `reference.txt`: the expected transcript.
- `say.txt`: the spoken text, including explicit macOS `say` pause instructions.
- `metadata.template.json`: the run metadata to complete before evaluation.

Each preparation gets a fresh capture UUID and a hash of the complete case definition.
It plays no audio and creates no recognition result.

## Recording protocol

Recording is a separate, explicitly authorized action.
Use [the isolated command interface](../../TESTING.md#command-interface-and-test-isolation), an already permitted local build, and a fresh private data directory.

For a synthetic loopback, use installed voices and the BlackHole prerequisites described in [TESTING.md](../../TESTING.md#live-loopback-test).
Record the original audio devices before changing routing.
Restore and verify them after every run, including failed runs.

The numbered-sentence `voice-test.sh` uses a different corpus.
Its coverage score does not benchmark recognition of these cases.

1. Select the reference locale in Dhwani and record the vocabulary hints actually used.
   Record the tested bundle's source SHA256 and full Git commit.
   Check the bundle itself; the current checkout may differ from the running app.
2. Copy the metadata template to a separate file for this run.
   Fill the OS version, hardware, exact installed voice name or identifier, voice locale, generator, speech rate, and relevant environmental notes.
   Do not download a missing voice as part of the benchmark setup.
3. Record `test_requested_at` in UTC and send `test-start:<UUID>`.
   Wait for that UUID's `listening` result and check that its microphone is the intended loopback.
   A refusal, another active capture, or a missing acknowledgement is a failed run.
4. Record `audio_started_at` immediately before playing the prepared `say.txt` with the recorded voice and rate.
   Record `audio_finished_at` immediately after playback ends.
5. Record `stop_requested_at` immediately before sending `test-stop:<UUID>`.
   Wait for the same UUID's final result.
   Keep failed and cancelled results alongside successful results.
6. Restore the original audio routing and verify it.
   Do not test automatic delivery while scoring recognition.

Use timezone-aware ISO 8601 timestamps, preferably with millisecond precision.
For example, a timestamp is `2026-10-07T10:00:12.345Z`.
Playback timestamps describe the interval observed by the harness, including configured pauses.
The result's capture duration also includes processing time, so it is not the playback duration.

Once the required permissions and routing are arranged, use the prepared prompt for synthetic playback:

`say -v '<installed voice>' -r 160 -f /tmp/talky-en-in-long-01/say.txt`

Record the exact value used for `-v`.
An `en-IN` reference alone does not establish that the synthetic voice had an Indian accent.

For real-microphone evidence, use only synthetic text or a separately consented sample.
Set `audio_source.kind` to `microphone` and provide `speaker_sample_id`, `environment`, and `consent` in the metadata.
Record speaking style, distance, microphone, noise conditions, and whether the reference was read verbatim.
Report synthetic loopback and real-microphone results as separate conditions.

## Evaluate a result

```bash
python3 -I test/benchmarks/benchmark.py evaluate \
  --case en-in-long-01 \
  --result /absolute/private-data/test-results/UUID.json \
  --metadata /absolute/run-metadata.json \
  --expected-run-id UUID \
  --output /absolute/new-report.json
```

The evaluator checks the expected UUID, selected case and locale, optional case hash, final capture phase, freshness, and timing order.
For loopback runs, it also checks the microphone identity.
Failed captures retain their scores, with `capture_succeeded` set to false.

Missing runtime metadata is listed and causes a failing exit status.
`--allow-incomplete-metadata` permits evaluation with missing fields, but leaves `runtime_metadata_complete` false.
The evaluator validates the provenance fields supplied by the caller.
It cannot independently prove which bundle, voice, hardware, or permissions were used.

| Exit status | Meaning |
| --- | --- |
| `0` | A successful final capture was evaluated with complete metadata, or incomplete metadata was explicitly allowed. |
| `1` | The capture failed or was cancelled, metadata was incomplete, or the requested error limit was exceeded. |
| `2` | Input was invalid or the report could not be written. |

Exit `0` does not establish acceptable recognition quality.
Use `--max-wer 0.15` to apply a caller-selected limit to `locale_v1` if needed.
The project has no established quality threshold yet.

Reports are written only to new files. An existing report is never overwritten.

## Scores and normalization

Word error rate is `(substitutions + deletions + insertions) / reference words`.
It can exceed 100 percent when insertions exceed the reference length.
The alignment finds the smallest number of edits.
When several choices tie, it prefers substitution, then deletion, then insertion.
Both scoring views are always reported.

### `lexical_v1`

This view uses Unicode NFKC normalization and case folding, straightens curly apostrophes, and keeps internal apostrophes within word tokens.
Dotted initials such as `A.M.` become `am`.
Punctuation and hyphens separate words and do not contribute to WER.

Grouped integers and decimals keep their written form as tokens.
For example, `42` differs from `forty two`.

### `locale_v1`

This view applies the same rules, then expands integers written in digits up to 999,999,999 without "and".
`en-US` uses million and thousand.
`en-IN` uses crore and lakh and accepts valid Indian or Western comma grouping.
Malformed grouping remains unchanged.

The spelling map merges colour/color, organise/organize, finalise/finalize, centre/center, metre/meter, normalise/normalize, and behaviour/behavior.
It includes the inflections listed in `benchmark.py`.

It does not add phonetic aliases for technical names, convert currencies, expand decimals or ordinals, remove spoken punctuation commands, or reinterpret number-word phrases.
Decimals such as `3.2` remain distinct from "three point two" in both views.

Locale normalization can reduce penalties for differences in written format.
Publish the lexical score beside it so those differences remain visible.
These are versioned scoring rules. Dhwani does not apply them to repair a transcript.

### Punctuation and exact text

Punctuation is a separate edit distance over the sequence of `. , ! ? ; :` marks.
It includes decimal points and does not measure where a mark belongs relative to words, quote matching, paragraph breaks, or grammar.
Check code, terminal commands, paths, capitalization, and executable syntax against the exact expected text.
A low WER or punctuation score does not establish that they are correct.
Delivery success is also separate from recognition and must be tested in the destination app.

### Missing and duplicated segments

Per-segment diagnostics use the locale-normalized alignment.
`possible_missing` means at least 75 percent of a segment's words were deleted.
An ambiguous alignment can make this a suspected omission rather than proof.

`exact_duplicate` means the entire normalized segment appears more than once in the recognized text.
Partial or altered repetitions may appear only as insertions and require transcript review.

Numbered-sentence coverage does not replace either word-error score.

### Completion latency

Completion latency measures the interval from the caller's stop request to the app's final result.
Dhwani currently writes timestamps to whole-second precision.
The evaluator uses the precision of both timestamps to report lower and upper bounds.
It cannot give a millisecond point estimate from a result recorded only to seconds.

## Repetition and publication

Run each selected case at least three times for each distinct locale, voice, model/settings, hardware, and audio condition.
Keep individual reports, failures, references, and run metadata.
For pooled WER, divide total edits by total reference words.
An unweighted average would give short and long cases equal influence.

Report completion latency with the bounds imposed by timestamp precision.
Report delivery checks separately.
Keep synthetic voices and human recordings separate, or label each condition clearly.

Before sharing evidence, check that it contains only synthetic or consented content.
Review environmental metadata for private information too.

Keep the corpus, evaluator, and fixture tests in the repository.
Keep private run outputs outside Git.

Run evaluator checks without recording:

```bash
python3 -I test/benchmarks/test_benchmark.py
```
