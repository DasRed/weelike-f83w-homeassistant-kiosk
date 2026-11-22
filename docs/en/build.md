---
title: Building the image
description: How tools/build_image.py builds the system image from the original GSI and src/, and how the "Build image" workflow publishes releases.
order: 50
slug: build
section: Details
---

The system image is not stored in the repository. It is built reproducibly from the original GSI, the Home Assistant
app and the files in `src/`. That is the job of
[`tools/build_image.py`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/tools/build_image.py),
usually in GitHub Actions.

## Sources

[`build/sources.json`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/build/sources.json)
defines what the image is built from, each with download URL and SHA-256:

| Source          | Version                                                         |
|-----------------|-----------------------------------------------------------------|
| GSI             | LineageOS 20 `a64_bvS` by AndyYan, build of 2025-10-21          |
| Home Assistant  | Companion for Android, "minimal" flavour, version 2026.8.4      |

If a checksum does not match, the build stops.

## Flow

The script needs neither root nor loop mounts; it works directly on the image file:

1. Download GSI and app (cached in `.cache/`) and compare the checksums.
2. Unpack the GSI, grow the ext4 image by 200 MB and resolve `shared_blocks`, otherwise it is not writable.
3. Modify it with `debugfs` in a single pass:
    - remove the apps from `src/removed-apps.txt`
    - add the app as a system app under `/system/app/HomeAssistant`, with its `armeabi-v7a` libraries extracted
    - write the files from `src/system-files.txt` with mode, owner and SELinux label
    - adapt `rw-system.sh` with `src/system/bin/rw-system.sh.patch`
    - append `src/product/build.prop.append` to `/system/product/etc/build.prop`
4. Check the file system and shrink it to its minimum size.
5. Optionally compress with `xz` and write `SHA256SUMS`.

## Build locally

This only works on Linux with `e2fsprogs`, `patch` and `xz`:

```bash
sudo apt-get install e2fsprogs patch xz-utils
python3 tools/build_image.py --version v9 --xz
```

| Option      | Default   | Description                                 |
|-------------|-----------|---------------------------------------------|
| `--version` | required  | version in the file name, e.g. `v9`         |
| `--out`     | `out/`    | output folder                               |
| `--cache`   | `.cache/` | folder for GSI and app                      |
| `--xz`      | off       | also create `.img.xz`                       |

## "Build image" workflow

[`.github/workflows/build-image.yml`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/.github/workflows/build-image.yml)
builds the image in three cases:

| Trigger                                                       | Result                                     |
|---------------------------------------------------------------|--------------------------------------------|
| Pull request changing `src/`, `build/` or the build script    | image as an artifact, kept for 3 days      |
| Push of a `v*` tag                                            | image as a GitHub release                  |
| Manual (Actions → Build image → Run workflow)                 | with a version, optionally as a release    |

The release notes name the commit, the GSI, the app version and the checksums.

## Publish a new version

1. Bring changes to `src/` or `build/sources.json` in via pull request. The workflow builds the image as a test.
2. After the merge, set the tag:

```bash
git tag v9
git push origin v9
```

3. Once the release is done, set `IMAGE_VERSION` in `flash.sh` to the new version.

> [!TIP]
> For a new version of the Home Assistant app it is enough to change `version`, `url` and `sha256` in
> `build/sources.json`.
