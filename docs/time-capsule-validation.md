# Cinema montage revision — validation

Reviewed range in both repositories: `origin/main...HEAD`, from the `cinema-v0.1.0` release to the montage revision tagged `cinema-v0.2.0`.

## Result

No unresolved code, test or content blockers. The app and bridge source can be released together. Installed apps and the running bridge still need updating; Apple TV hardware validation remains outstanding.

## Checks

- Native iOS simulator build and full test run passed (146 tests reported); the six Time Capsule tests also passed in an explicit focused run.
- Shared native/tvOS sources passed tvOS SDK type checking. No tvOS simulator runtime is installed here.
- iPhone and iPad simulators displayed real archive photographs and advanced between headlines. Music pause held the current photograph; the model tests cover resume timing, wraparound and continuity independent of song identity.
- Bridge: all 451 configured tests, workspace lint and production builds passed. The 12 focused capsule tests cover request anchoring, evidence links, event/photo dates, explicit image IDs, duplicate references, visual-review rejection, failed rebuild preservation and HTTP access.
- Each configured TypeScript workspace passed its own installed compiler with its own project configuration.
- A live external request for 24–30 June 2007 was researched and illustrated. The final visual review retained six photographs and rejected an obviously blurred original. This checks retrieval and playback, not comprehensive coverage of every event that week. No example content is bundled in the product.
- Changed interface copy, source links, rebuild route and request preservation were manually reviewed. Existing manifests can be rebuilt without changing their original request or room association.

## Generic content-gate findings

The pre-main script ran against `origin/main...HEAD` in both repositories. Its native check passed; native build/tests above supplement its lack of Xcode detection. The bridge script reported two tooling false positives, resolved by the checks below:

1. It treated the Fastify integration-test URL `/paired/time-capsules/saved/rebuild` as a missing static website file. The registered `/:id/rebuild` handler is exercised by the passing route test; this is not a document link.
2. Root `npx tsc --noEmit` resolved the unrelated npm package named `tsc`, rather than the workspace TypeScript compiler. Explicit calls to the installed TypeScript compiler passed for API, Angular app, model and client workspaces. Full production builds passed too.

The reported external 404s are deliberate mock/example image URLs in tests, never production asset sources. The existing Angular initial-bundle size warning (947.50 kB against an 870.40 kB budget) remains unchanged. The generic script's failure is therefore not reported as a clean automated gate; the relevant route and compiler checks were resolved manually.
