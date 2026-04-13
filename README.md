# ModelsBar

English | [简体中文](README_zh.md)

`ModelsBar` is a native macOS menu bar app for checking model lists, key health, quota usage, and connectivity across NewAPI, Sub2API, and OpenAI-compatible services.

## Contents

- [Features](#features)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Recommended Workflow](#recommended-workflow)
- [Usage Notes](#usage-notes)
- [About](#about)

## Features

- Runs in the macOS menu bar for quick access.
- Supports multiple NewAPI, Sub2API, and OpenAI-compatible endpoints.
- Supports multiple API keys under the same provider.
- Syncs model lists, quotas, and daily usage data.
- Tests model connectivity to help identify invalid keys or unavailable models.
- Includes a dedicated Settings window for managing providers, keys, and status.
- Includes an About window with app summary, version, author, and license information.

## Installation

1. Download the `.dmg` package for your CPU architecture from the Releases page.
2. Download the `arm64` build for Apple Silicon Macs.
3. Download the `x86_64` build for Intel Macs.
4. Open the downloaded `.dmg`.
5. Move `ModelsBar.app` into the `Applications` folder.
6. Open the app from `Applications`.

If macOS shows a security prompt, confirm it through the standard macOS open dialog.

## Getting Started

After launching ModelsBar for the first time, complete the following steps:

1. Click the menu bar icon to open the main panel.
2. Open `Settings`.
3. Add your provider endpoint and credentials.
4. Add one or more API keys for that provider.
5. Sync data and review the detected models, quotas, and current status.

## Recommended Workflow

1. Prepare your NewAPI, Sub2API, or OpenAI-compatible endpoint.
2. Install ModelsBar.
3. Add the provider in `Settings`.
4. Add or sync API keys.
5. Refresh models and quota information.
6. Run connectivity tests when needed.

## Usage Notes

- ModelsBar is designed for quick status checking directly from the macOS menu bar.
- If a provider or key becomes unavailable, refresh the data first and then run a model connectivity test.
- Use the Settings window to manage multiple providers and keys in one place.
- Use the About window to quickly confirm the current app version and release information.

## About

- Author: `htnanako`
- License: `MIT`
