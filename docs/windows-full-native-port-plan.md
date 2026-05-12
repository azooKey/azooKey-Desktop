# Windows Native Port Plan (Full Feature Parity)

This document starts execution of the Windows native-port roadmap by defining **Task 1** in implementation-ready form.

## Scope of this step

Implementable requirements for feature parity of the conversion core:

- Segment management parity.
- Mis-conversion correction flow parity.
- Predictive candidate generation parity.
- Candidate ranking/re-ranking parity.
- Post-commit context reflection parity.

## Source-of-truth mapping (macOS -> Windows)

Primary reference behavior currently lives in:

- `Core/Sources/Core/InputUtils/SegmentsManager.swift`

Windows implementation target modules:

- `core/` (platform-neutral interfaces and behavior contracts)
- `inference-host/` (runtime orchestration + session context)
- `ipc/` (context transport contract)
- `tests/` (golden parity tests)

## Functional requirements

### 1. Session-aware conversion API

Add/extend conversion operations so Windows path supports:

- `convert(input, context)`
- `predict(input, context)`
- `correct(input, correction_hint, context)`
- `commit(selected_candidate, context)`

`context` must include at minimum:

- Pre-edit buffer state.
- Prior committed text window (N-gram context).
- Candidate selection history in current session.

### 2. Segment lifecycle parity

Windows route must preserve segment lifecycle semantics:

1. Initial segmentation from pre-edit text.
2. Candidate generation per segment.
3. Re-segmentation when user correction intent is detected.
4. Segment merge/split under correction/backspace patterns.
5. Stable segment IDs to avoid UI flicker while candidates refresh.

### 3. Mis-conversion correction behavior

Correction flow requirements:

- Detect correction-trigger patterns from user actions.
- Re-rank candidates with correction intent weight.
- Avoid repeating recently rejected candidates at the top.
- Persist correction signal as a learning event (future task wiring in `learning/`).

### 4. Predictive conversion behavior

Prediction requirements:

- Generate prediction candidates on incremental input.
- Blend lexical and model-based predictions under one ranking surface.
- Preserve deterministic fallback when model inference is unavailable.
- Return category labels/flags for UI grouping.

### 5. Candidate ranking contracts

Define ranking output contract for host/TIP compatibility:

- Candidate string
- Reading/key
- Score (normalized)
- Source kind (system dictionary/user dictionary/model/llm)
- Debug metadata (optional, behind dev flag)

## Test plan for this step

### Golden parity tests

Create fixtures that compare macOS-reference outputs and Windows outputs for:

- Basic conversion sequences.
- Incremental predictive typing.
- Backspace and correction sequences.
- Repeated rejection/reselection behavior.

### Acceptance criteria

Task 1 is considered complete when:

- API contracts are implemented and compiled on Windows build.
- Golden tests exist and run in CI.
- Known differences are explicitly listed in test expectations.

## Follow-up tasks unlocked by this step

- Task 2: learning/personalization pipeline wiring. *(in progress: IPC message contracts for predict/correct/commit-correction/user-dictionary update have been added in `ipc/`.)*
- Task 3: user dictionary management and hot reload.
- Task 6: CUDA backend integration with stable fallback.
