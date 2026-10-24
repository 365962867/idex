# iDex icon

Run from the repository root:

```sh
swift scripts/icon/generate_icon.swift
```

The generator uses AppKit/CoreGraphics only. It produces the app's opaque, 1024 × 1024 sRGB PNG in `iDex/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

The red moulded shell, machined blue lens, three indicator lamps, inset LCD, pixel ball and scan reticles, screw heads, rubber controls, and speaker slots are drawn from vectors. The app icon has no transparent pixels and fills the square canvas; iOS applies its app-icon mask. A deterministic fine grain gives the plastic a restrained texture. No remote images, generated artwork, or third-party icon assets are used.
