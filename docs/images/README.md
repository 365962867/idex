# README visuals

The banner and social preview reuse iDex's existing app icon and bundled Press Start 2P font. They are decorative graphics, not screenshots. The icon's vector source is in [scripts/icon](../../scripts/icon/README.md); font and Pokémon credits remain in [asset attribution](../../iDex/Catalog/ATTRIBUTION.md).

| Asset | Size | Use |
| --- | --- | --- |
| [banner.png](banner.png) | 1600 × 560 | README header |
| [social-preview.png](social-preview.png) | 1280 × 640 | Optional repository social preview |

Regenerate both on macOS from the repository root:

```sh
swift scripts/readme/generate_assets.swift
```

## Screenshots

The five PNGs in [docs/screenshots](../screenshots) are unedited UI-test attachments captured on 24 October 2026 using Xcode 27.1 and the iPhone Duo iOS 27.1 simulator. They show the cover display, with audio muted. The scanner sample is explicitly labelled in the app and passes through real bundled-model inference. The Chinese Charizard record is browsed from the archive, not a camera recognition result. These captures do not validate a physical camera or hinge transition.

To capture a fresh set, run from the repository root with the simulator folded. Choose a new result-bundle path if one already exists:

```sh
xcodebuild test -project iDex.xcodeproj -scheme iDex \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -parallel-testing-enabled NO \
  -only-testing:iDexUITests/iDexUITests/testSampleIsIdentifiedByBundledModel \
  -only-testing:iDexUITests/iDexUITests/testRecordFillsCoverDisplayAndCloses \
  -only-testing:iDexUITests/iDexUITests/testCatalogSearchAcceptsEnglishChineseAndDexNumber \
  -resultBundlePath artifacts/readme/Screenshots.xcresult

python3 scripts/readme/export_screenshots.py artifacts/readme/Screenshots.xcresult
```

All three selected tests passed for the checked-in captures. Result bundles and build logs stay under ignored `artifacts/`; the selected screenshots live in `docs/` so GitHub can display them.
