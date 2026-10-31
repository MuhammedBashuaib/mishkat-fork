# Local speech_to_text 7.5.0 patch

Upstream: https://github.com/csdcorp/speech_to_text (pub.dev 7.5.0).
The upstream BSD license is retained in `LICENSE`.

Android recognition now releases each native recognizer before a new utterance,
including after an error has already marked it as not listening. Native actions
complete on the main thread before their method response. Generation-scoped
listeners and silence timers discard callbacks from a cancelled session. This
also removes a delayed teardown which could destroy the next recognizer. The
recognition intent cache includes the offline preference.

Apple recognition delegates now check task identity before delivering results,
errors, or stopping audio. Cancellation detaches the task before invoking the
native cancel operation; stopped tasks are released even when the listening flag
has already been cleared. Sound completion callbacks are scoped to the session.
Unsupported on-device recognition returns immediately rather than falling through
to start a request after reporting failure.

`ListenFailedException` retains the native error code so the application can
distinguish unavailable offline recognition from microphone or startup errors.

Production Dart, Darwin and Android sources are included; upstream examples and
development artifacts are omitted. Keep this patch until equivalent upstream
fixes are verified.

Native Android regression checks:

```sh
cd android
./gradlew :speech_to_text:testDebugUnitTest
```
