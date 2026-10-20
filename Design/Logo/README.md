# Vigil — logo kit (Direction B · Three rings)

Three open rings, gap at the top. Outer = Recovery, middle = Sleep, inner = Strain.
All artwork is vector; PNGs are rendered from the SVGs. The wordmark is outlined (no font needed).

## Contents

| Path | Use |
|---|---|
| `png/AppIcon-1024-light.png` | iOS app icon, **Any / Light** appearance (full-bleed square, iOS applies the corner mask) |
| `png/AppIcon-1024-dark.png` | iOS app icon, **Dark** appearance (opaque) |
| `png/AppIcon-1024-dark-transparent.png` | Dark appearance, transparent background (Apple's preferred style for dark icons) |
| `png/AppIcon-1024-tinted.png` | **Tinted** appearance (grayscale on black; iOS colorizes it) |
| `icon-composer-layers/*.svg` | Separate layers for **Icon Composer** (iOS 26+ Liquid Glass / Clear icons): background + one ring per layer |
| `svg/vigil-appicon-*.svg` | Vector sources of the icons above |
| `svg/vigil-appicon-small.svg`, `png/AppIcon-small-detail-180.png` | Simplified 2-ring version for very small sizes (≤ 40 pt, e.g. Settings, notifications) if the 3-ring one gets muddy |
| `svg/vigil-mark-color.svg` / `-on-dark.svg` | The rings alone, transparent — for splash screen, onboarding, empty states |
| `svg/vigil-mark-mono.svg` | Single-color mark using `currentColor` — for SF-Symbol-like / template use |
| `svg/vigil-wordmark.svg` | "Vigil" wordmark alone, `currentColor` |
| `svg/vigil-logo-lockup-light.svg` / `-dark.svg` (+ PNGs) | Mark + wordmark, for About screen, App Store art, README |
| `png/preview-rounded-512.png` | Rounded preview only — **do not** put in the asset catalog |

## Colors

| Token | On light | On dark |
|---|---|---|
| Recovery (outer ring) | `#1DB872` | `#3FE3A0` |
| Sleep (middle ring) | `#7B61FF` | `#9D8CFF` |
| Strain (inner ring) | `#FF6A3D` | `#FF6A3D` |
| Icon background | `#FFFFFF` | `#17161F` |
| Wordmark | `#12141A` | `#FFFFFF` |

## Geometry (100 × 100 canvas)

- Ring centre: (50, 52) — nudged 2 units down to balance the top gap.
- Radii 33 / 22 / 11, stroke 8, round caps.
- Each ring covers 300°, gap of 60° centred at 12 o'clock (`stroke-dasharray` = 5/6 of circumference, rotated −60°).
- Wordmark: Bricolage Grotesque ExtraBold (96 pt optical size), tracking −3.5 %, cap height = 40 % of the mark height, 18-unit gap.

## Instructions (Xcode)

1. In `Assets.xcassets`, open **AppIcon** → set iOS to **Single Size**, and enable **Dark** and **Tinted** appearances.
2. Drop `AppIcon-1024-light.png` into *Any Appearance*, `AppIcon-1024-dark-transparent.png` (or `-dark.png`) into *Dark*, and `AppIcon-1024-tinted.png` into *Tinted*.
3. For iOS 26 Liquid Glass (Clear) icons: create a new `.icon` file in **Icon Composer**, import `0-background-*.svg` as the background and the three ring SVGs as separate layers (outer, middle, inner) so each ring gets its own glass depth; add the `.icon` file to the Xcode project and select it as the app icon.
4. Add `vigil-mark-color.svg` (and `-on-dark.svg` as the dark variant) as an image set with "Preserve Vector Data" for in-app use (onboarding, splash, Profile header).
5. Do not round the corners or add a shadow yourself — iOS does that.
