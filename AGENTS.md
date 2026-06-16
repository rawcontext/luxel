# AGENTS.md

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## Guiding Principles
- Always verify today's date to avoid a temporal paradox.
- When rebuilding or relaunching Luxel, always build and launch a properly signed `.app` bundle using the user's Apple Development identity (for example via `Scripts/build-luxel-app.sh`). Never launch the SwiftPM debug executable (`.build/arm64-apple-macosx/debug/Luxel`) or any ad-hoc-signed binary, because it breaks macOS TCC permissions and causes repeated permission prompts. If signing or launching the signed bundle fails, stop and report that failure instead of using an unsigned/ad-hoc fallback.
- Do Your Own Exploration - Verify assumptions against actual codebase, tests, and documentation.
- Use Context7 for Documentation - Always query context7 for up-to-date library/service/API docs.
- Ground Assumptions with Research - Use web search to verify syntax, patterns, version compatibility, and best practices instead of making assumptions.
- Trust self-documenting code. Do not add comments that restate what the code does. Only add comments when explaining why something non-obvious is necessary.
- Do NOT modify linting rules or code coverage requirements without explicit approval.

## Package Versions

- Before installing any package, look up the current version on its authoritative registry (npm, crates, etc.). Never guess or use a version from memory.
- Always install the latest stable version. Do not pin to older versions unless a specific incompatibility requires it, and document why.
- When updating existing packages, check the registry first — do not assume the currently installed version is current.
