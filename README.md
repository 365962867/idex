# iDex

A native, bilingual pocket Pokédex for iPhone Duo. Built with SwiftUI, AVFoundation, Core ML, and local speech synthesis. An unofficial fan project.

## Run

Open `iDex.xcodeproj` in Xcode 27.1, select the **iDex** scheme and **iPhone Duo** simulator, then Run. There are no packages, API keys, server, or runtime downloads to configure. The app target supports iOS 27 and newer; hinge observation uses iOS 27.1 when available.

On a physical iPhone, iDex requests camera access and starts the viewfinder. In Simulator, it starts with an explicitly labelled Pikachu sample because there is no rear camera. Tap **Identify** to run that sprite through the actual bundled Core ML model. Camera, Photo Library, and Sample controls switch sources. Importing a photo immediately runs recognition. A frozen capture is labelled **Photo review**; **Live** returns to the camera.

Unfolding reveals the archive on the left. The viewfinder uses a fixed 466-point panel anchored to the right edge, with its own fixed 320-point square at y=179. The 951×669 expanded layout adds a 466-point left panel and 19-point hinge, preserving the scanner's right-edge inset, vertical position, and size from the 466×678 cover display. The camera controller lives above both layout states. UIKit's `UIHingeInteraction` observes hardware hinge updates, gates the interior reveal, and plays the opening sound; it never requests a rotation. The app locks both displays to Duo's native holding orientation (`.portrait` in UIKit's orientation coordinates). The system maps each display's native rotation; a wider interior canvas does not opt into landscape-left or landscape-right autorotation. The layout also requires enough width and height for both panels, so rotating the closed cover cannot reveal a cramped archive.

A closed scan shows the entry in a dismissible full-screen record. Opening the device dismisses that compact record so the inside becomes visible. **Open record** also gives access to the archive while closed. Search in either language by name, dex number, or localized type. Browse records with the arrow buttons, switch field notes to base stats, and use Read/Stop for narration.

Settings offers English / 简体中文 and a sound toggle. Names, types, notes, controls, camera privacy text, pixel fonts, and speech use the selected language. The first launch follows the system language. Language, sound, last-viewed species, and discovered species IDs persist locally. Photos remain in memory and are never uploaded or written to an app photo archive. System speech uses installed voices; a desired voice may need to be installed in iOS Settings for offline speech.

## Recognition scope

The app includes a roughly **14 MB FP16 DenseNet121 Core ML model for the original 151 Kanto species**. It computes predictions on the device and abstains when score and separation heuristics are weak. Only accepted results are marked discovered or automatically narrated. Uncertain results show possible candidates and ask for a clearer image.

This is a 151-class model without a trained unknown/background class. Unrelated objects and non-Kanto Pokémon can still produce false matches. Camera accuracy across toys, cards, lighting, and viewpoints needs physical-device evaluation. The model score is not a calibrated probability. See [model provenance and reproduction](iDex/Recognition/MODEL.md).

## Tests and visual checks

Run Product → Test, or:

```sh
xcodebuild test -project iDex.xcodeproj -scheme iDex \
  -destination 'platform=iOS Simulator,name=iPhone Duo'
```

The tests exercise real bundled-model inference and blank-image abstention, catalog completeness, every sprite, both fonts, Chinese and English search and prompts, layout continuity, language persistence, discovery display, and archive selection. The UI tests explicitly mute audio to keep automated runs quiet.

`ContentView.swift` contains named SwiftUI previews at the Duo cover and expanded dimensions. The physical camera and an actual fold transition still require device testing; rendered expanded previews and geometry tests do not prove physical continuity.

Duo exposes two integrated displays. To capture its folded cover screen, specify `--display=1`; the default screenshot may select the inactive interior display and return black.

```sh
xcrun simctl io booted screenshot --display=1 /tmp/idex-cover.png
```

## Assets and attribution

- [Pokémon Database sprites](https://pokemondb.net/sprites): all 151 Black/White pixel sprites bundled offline.
- [PokéAPI](https://github.com/PokeAPI/pokeapi): species names, bilingual flavor text, dimensions, types, and stats.
- Press Start 2P and Fusion Pixel: bundled Latin and Simplified Chinese pixel fonts under SIL OFL 1.1, with license files.
- [BiernyVR's classifier](https://huggingface.co/BiernyVR/pokemon-classifier-mobilenetv3): pinned DenseNet121 checkpoint, with upstream MIT metadata and documented conversion.
- Physical-device inspiration: [Stuff's DIY Pokédex article](https://stuff.co.za/2026/04/15/the-pokedex-is-real-and-fully-functional-but-youd-have-to-build-your-own/) and [Pokebattler's Pokédex reference](https://articles.pokebattler.com/2018/08/30/pogo-pokedex-by-the-numbers/).

See [catalog attribution](iDex/Catalog/ATTRIBUTION.md), [model notes](iDex/Recognition/MODEL.md), and `scripts/` for reproducible catalog, model, and app-icon generation. Pokémon and related characters belong to Nintendo, Creatures, GAME FREAK, and The Pokémon Company. iDex is not affiliated with or endorsed by them.
