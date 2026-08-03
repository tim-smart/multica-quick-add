# Multica Quick Add

A native macOS app for quickly creating issues in Multica.

## Requirements

- macOS 14 or newer
- Xcode
- [Nix](https://nixos.org/) with flakes enabled
- [direnv](https://direnv.net/) (recommended)

The Nix development shell installs XcodeGen. Swift, SwiftUI, and `swift-format` are provided by Xcode so they use the selected macOS SDK.

## Setup

```sh
direnv allow
make bootstrap
```

Open the app in Xcode with:

```sh
make open
```

## Commands

- `make build` builds the app without requiring a signing identity.
- `make test` runs the unit tests.
- `make format` formats the Swift sources.
- `make lint` verifies Swift formatting.
- `make generate` regenerates the Xcode project after editing `project.yml`.
