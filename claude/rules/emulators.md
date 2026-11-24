## Emulators: shut down as soon as testing is done

An Android emulator or iOS Simulator takes several GB of RAM and keeps a few cores busy even when idle. One left running next to a native build pushed the Mac out of RAM and swap (user, 24 Nov 2026: "emulation has to be closed as soon as done testing because it eats up a lot of resources").

- Boot an emulator only when you are about to test on it. Shut it down as soon as that testing ends: `adb -s <serial> emu kill` for Android, `xcrun simctl shutdown <udid>` for iOS.
- This includes testing that fails or stops to wait for something (a review, a fix, the user). Boot it again when you next need it.
- After a native build, stop the Gradle daemon (`./gradlew --stop` from the android folder). It keeps several GB after the build ends.
- Before your final reply, check that nothing you started is still running (`adb devices`, `xcrun simctl list devices booted`).
- Never shut down an emulator another session is using. If one is already running, reuse it instead of booting a second one.
