# Android APK Reference — Kotlin + Compose Multiplatform (stellar-trail companion blueprint)

> Blueprint for a stellar-trail companion Android APK: proper module structure,
> dependency set (version catalog), and a GitHub Actions build workflow. Reference
> only — nothing in the skill currently builds Android; this file exists so a future
> companion app starts from a correct, doctrine-aligned skeleton (v5.7.3, Task 74).
> Not in the M0 read path.

## 1. Scope & doctrine carryovers

- **Stack:** Kotlin · Compose Multiplatform (CMP) · Gradle version catalog · single-activity UI · Koin DI.
- **Doctrine alignment:** the companion mirrors the Task Files Explorer, not a generic app —
  a dashboard of stat tiles + a task rail over the ledger, dark `#17171A` / light `#EFEFEF`
  surfaces with cards `#2c2c2c` / `#FFFFFF` (the owner-tuned D10 palette), and **zero popups**:
  feedback goes through an accessibility live region (the Task-69 announce doctrine), never
  floating snackbars or dialogs outside the file-preview surface.
- **Version policy:** the catalog below pins MAJOR LINES only (resolved current at authoring
  time, 2026-11) — pin exact patches when the project actually starts, and let Dependabot/renovate ride.

## 2. Proper module structure (CMP)

```text
stellar-trail-android/
├── settings.gradle.kts               # repositories + module includes
├── build.gradle.kts                  # root: plugin aliases only
├── gradle.properties                 # AndroidX, JVM args, KMP flags
├── gradle/
│   ├── libs.versions.toml            # THE version catalog (single source of truth)
│   └── wrapper/                      # gradle-wrapper.jar + properties
├── shared/                           # KMP shared module — domain + data (UI-free)
│   └── src/
│       ├── commonMain/kotlin/com/stellartrail/shared/
│       │   ├── model/                # TaskState, SealedVerdict, ReleaseInfo (kotlinx-serialization)
│       │   ├── repository/           # LedgerRepository: parses worklog.md + SESSION-STATE.md
│       │   └── util/                 # grep-first line parser (mirrors the ledger format)
│       ├── androidMain/kotlin/…      # Android drivers (file access, datastore)
│       └── iosMain/kotlin/…          # iOS glue (future CMP target)
├── composeApp/                       # UI module — single-activity Compose
│   └── src/
│       ├── commonMain/kotlin/com/stellartrail/app/
│       │   ├── App.kt                # root composable: NavHost + theme
│       │   ├── ui/theme/             # Color.kt (D10 palette) · Theme.kt · Type.kt
│       │   ├── ui/navigation/        # Screen (sealed) · NavGraph.kt
│       │   ├── ui/screens/           # DashboardScreen · TaskDetailScreen · ReleaseScreen
│       │   ├── ui/components/        # StatTile · TaskRail · AnnounceHost (live region)
│       │   └── di/                   # Koin module definitions (common)
│       ├── androidMain/kotlin/…/
│       │   ├── MainActivity.kt       # setContent { App() } + edge-to-edge
│       │   ├── AppApplication.kt     # Koin startup
│       │   └── announce/             # Android viewAccessibility bridge for the live region
│       └── androidMain/AndroidManifest.xml
├── app-dist/                         # (gitignored) signing + assembled APKs
└── .github/workflows/android-build.yml
```

Why two modules: `shared` stays UI-free and testable in common tests; `composeApp` hosts
all Compose code with `commonMain` shared for a future iOS/desktop target — the standard CMP layout.

## 3. Key build files

`settings.gradle.kts`:
```kotlin
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "stellar-trail-android"
include(":shared", ":composeApp")
```

`composeApp/build.gradle.kts` (essentials):
```kotlin
plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeCompiler)      // Kotlin 2.x Compose compiler plugin
    alias(libs.plugins.composeMultiplatform) // org.jetbrains.compose
}
kotlin {
    androidTarget { unitTests.all { it.useJUnitPlatform() } }
    // add iosTarget() when the iOS target starts
    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime); implementation(compose.foundation)
            implementation(compose.material3); implementation(compose.components.resources)
            implementation(projects.shared)   // or implementation(project(":shared")) on older Gradle
            implementation(libs.koin.compose)
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.voyager.navigator)      // CMP-friendly navigation
            implementation(libs.coil3.compose)          // async images (icons/previews)
            implementation(libs.kermit.logging)
        }
    }
}
android {
    namespace = "com.stellartrail.app"
    compileSdk = 35
    defaultConfig { applicationId = "com.stellartrail.app"; minSdk = 26; targetSdk = 35 }
    buildTypes {
        release {
            isMinifyEnabled = true; isShrinkResources = true
            // signing from env/secrets — see §5 CI; never commit keystores
        }
    }
}
```

## 4. Version catalog — `gradle/libs.versions.toml`

```toml
[versions]
agp = "8.7"                       # Android Gradle Plugin — major line
kotlin = "2.1"                    # Kotlin 2.x required for the Compose compiler plugin
composeMultiplatform = "1.7"      # org.jetbrains.compose
coroutines = "1.9"
serialization = "1.7"
koin = "4.0"
voyager = "1.1"
coil3 = "3.0"
kermit = "2.0"
datastore = "1.1"                 # androidx.datastore preferences (androidMain)
ktor = "3.0"                      # optional: remote ledger fetch
junit = "5.11"

[libraries]
kotlinx-coroutines-core = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-core", version.ref = "coroutines" }
kotlinx-coroutines-android = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-android", version.ref = "coroutines" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "serialization" }
koin-compose = { module = "io.insert-koin:koin-compose", version.ref = "koin" }
voyager-navigator = { module = "cafe.adriel.voyager:voyager-navigator", version.ref = "voyager" }
coil3-compose = { module = "io.coil-kt.coil3:coil-compose", version.ref = "coil3" }
kermit-logging = { module = "co.touchlab:kermit", version.ref = "kermit" }
datastore-preferences = { module = "androidx.datastore:datastore-preferences", version.ref = "datastore" }
ktor-client-core = { module = "io.ktor:ktor-client-core", version.ref = "ktor" }
ktor-client-okhttp = { module = "io.ktor:ktor-client-okhttp", version.ref = "ktor" }
junit-jupiter = { module = "org.junit.jupiter:junit-jupiter", version.ref = "junit" }

[plugins]
kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
kotlinSerialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
androidApplication = { id = "com.android.application", version.ref = "agp" }
composeCompiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
composeMultiplatform = { id = "org.jetbrains.compose", version.ref = "composeMultiplatform" }
```

## 5. CI build workflow — `.github/workflows/android-build.yml`

```yaml
name: Android Build
on:
  push:
    branches: [main]          # bracket the filter list — a bare-string filter
    tags: ['v*']              # is a silent foot-gun (never fires as intended)
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4   # cached wrapper, build caching
      - name: Unit tests (shared + common)
        run: ./gradlew :shared:allTests :composeApp:testDebugUnitTest --stacktrace
      - name: Assemble release APK (unsigned when no signing env)
        run: ./gradlew :composeApp:assembleRelease --stacktrace
      - name: Sign (secrets only — never commit keystores)
        if: startsWith(github.ref, 'refs/tags/v')
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: |
          echo "$KEYSTORE_BASE64" | base64 -d > app-dist/release.jks
          ./.github/scripts/sign-apk.sh app-dist/release.jks   # apksigner with env creds
      - uses: actions/upload-artifact@v4
        with:
          name: stellar-trail-apk
          path: composeApp/build/outputs/apk/release/*.apk
      - name: Attach to GitHub release (tags only)
        if: startsWith(github.ref, 'refs/tags/v')
        env: { GH_TOKEN: '${{ github.token }}' }
        run: gh release upload "${GITHUB_REF_NAME}" composeApp/build/outputs/apk/release/*.apk --clobber
```

Signing rules: the keystore exists ONLY as a base64 secret; CI decodes to a temp file and
signs with `apksigner`; nothing key-shaped is ever committed (same doctrine as the skill's
PAT handling — secrets live in the credential store, not the tree).

## 6. Concept mapping (explorer → companion)

| Task Files Explorer (web) | Companion APK |
|---|---|
| Dashboard stat tiles | `StatTile` grid on `DashboardScreen` |
| Task rail (merged worklog + archive) | `TaskRail` list from `LedgerRepository` |
| `ui.announce` sr-only aria-live | `AnnounceHost` — `Modifier.semantics { liveRegion = LiveRegionMode.Polite }` |
| preview modal (the only popup) | `TaskDetailScreen` — a navigation destination, never a dialog |
| `?inline=1` modal-only media | Coil3 async image inside the detail screen |
| theme system dark/light | `Theme.kt` with the D10 palette + `isSystemInDarkTheme()` |

## 7. Non-goals (honest limits)

- No push notifications, no background sync, no wearable target — the companion is a READ surface over the ledger files.
- The iOS/desktop CMP targets are scaffolded by the module layout but not built until the owner orders them.
- This blueprint does not vendor any Google-Play-specific plumbing (billing, Play Integrity, Play releases); if a store distribution is ever ordered, it gets its own reference section.
