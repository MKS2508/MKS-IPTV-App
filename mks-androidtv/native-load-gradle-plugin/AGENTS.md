# AGENTS.md

This file applies to the entire `native-load-gradle-plugin` repository.

## Scope

This repository contains the `dev.oxyroid.native-load` Gradle plugin. It:

- Parses root-level `native-load.yml`.
- Configures Android library `BuildConfig` native-pack metadata.
- Instruments Android application bytecode for native library load redirection.
- Generates committed native pack zip assets and manifests from configured AAR artifacts.

## Engineering Rules

- Use Kotlin only. Do not add Java.
- Keep the plugin small and focused on native-load configuration, instrumentation, and pack generation.
- Prefer Gradle lazy APIs and task inputs/outputs. Avoid execution-time `Project` access in task actions when changing task behavior.
- Keep Android Gradle Plugin interactions on public AGP APIs.
- Do not add host-app UI, data, or business behavior here.
- Do not use star imports.
- Keep package-qualified references in imports, using import aliases for conflicts.
- Add dependencies through Gradle catalogs or existing repositories only. Do not add jar files, unknown Maven repositories, or inline dependency versions unless this standalone plugin explicitly needs them.

## Native Pack Behavior

- Treat `native-load.yml` as the source of truth for artifacts, libraries, load order, instrumentation prefixes, and output paths.
- `pack.loadOrder` must only contain libraries declared in `pack.libraries`.
- Native library names in config omit both the `lib` prefix and `.so` suffix.
- Pack generation resolves configured AAR artifacts non-transitively and extracts only `jni/<abi>/*.so` entries.
- Generated manifests and zip files should remain deterministic: stable sort order, stable paths, and stable hashes.

## Validation

- For plugin changes, run the smallest relevant Gradle check first.
- When changing pack generation or instrumentation in the parent workspace, validate from the parent root with:

```bash
./gradlew :app:smartphone:generateReleaseNativePacks --no-configuration-cache
```

- For task registration changes, also inspect:

```bash
./gradlew :app:smartphone:tasks --all --no-configuration-cache
```

- If generated native packs change, verify whether `native-packs/**` should be updated in the parent repository.

## Git And Submodule Notes

- This repository may be consumed as a submodule by a parent repository.
- Commit plugin changes inside this repository first, then update and commit the submodule pointer in the parent repository when applicable.
- Do not rewrite history or force-push unless the user explicitly asks.
