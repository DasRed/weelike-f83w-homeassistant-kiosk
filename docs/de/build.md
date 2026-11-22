---
title: Image bauen
description: Wie tools/build_image.py das System-Image aus Original-GSI und src/ baut und wie der Workflow „Build image“ Releases veröffentlicht.
order: 50
slug: image-bauen
section: Details
---

Das System-Image liegt nicht im Repository. Es entsteht reproduzierbar aus dem Original-GSI, der Home-Assistant-App
und den Dateien in `src/`. Das erledigt
[`tools/build_image.py`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/tools/build_image.py),
normalerweise in GitHub Actions.

## Quellen

[`build/sources.json`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/build/sources.json) legt
fest, woraus gebaut wird, jeweils mit Download-Adresse und SHA-256:

| Quelle          | Stand                                                              |
|-----------------|--------------------------------------------------------------------|
| GSI             | LineageOS 20 `a64_bvS` von AndyYan, Build vom 21.10.2025            |
| Home Assistant  | Companion for Android, Variante „minimal“, Version 2026.8.4         |

Stimmt eine Prüfsumme nicht, bricht der Build ab.

## Ablauf

Das Skript braucht weder Root noch Loop-Mounts, es arbeitet direkt auf der Image-Datei:

1. GSI und App laden (mit Cache in `.cache/`) und die Prüfsummen vergleichen.
2. Das GSI entpacken, das ext4-Image um 200 MB vergrößern und `shared_blocks` auflösen, sonst ist es nicht
   beschreibbar.
3. Mit `debugfs` in einem Durchgang ändern:
    - die Apps aus `src/removed-apps.txt` entfernen
    - die App als System-App unter `/system/app/HomeAssistant` ablegen, ihre `armeabi-v7a`-Bibliotheken entpackt
    - die Dateien aus `src/system-files.txt` schreiben, mit Rechten, Besitzer und SELinux-Label
    - `rw-system.sh` mit `src/system/bin/rw-system.sh.patch` anpassen
    - `src/product/build.prop.append` an `/system/product/etc/build.prop` anhängen
4. Das Dateisystem prüfen und auf die kleinstmögliche Größe schrumpfen.
5. Optional mit `xz` packen und `SHA256SUMS` schreiben.

## Lokal bauen

Das geht nur unter Linux mit `e2fsprogs`, `patch` und `xz`:

```bash
sudo apt-get install e2fsprogs patch xz-utils
python3 tools/build_image.py --version v9 --xz
```

| Option      | Standard  | Beschreibung                                    |
|-------------|-----------|-------------------------------------------------|
| `--version` | Pflicht   | Version im Dateinamen, z. B. `v9`               |
| `--out`     | `out/`    | Zielordner                                      |
| `--cache`   | `.cache/` | Ordner für GSI und App                          |
| `--xz`      | aus       | zusätzlich `.img.xz` erzeugen                   |

## Workflow „Build image“

[`.github/workflows/build-image.yml`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/.github/workflows/build-image.yml)
baut das Image in drei Fällen:

| Auslöser                                            | Ergebnis                                         |
|-----------------------------------------------------|--------------------------------------------------|
| Pull Request mit Änderungen an `src/`, `build/` oder am Build-Skript | Image als Artefakt, 3 Tage aufbewahrt |
| Tag `v*` gepusht                                    | Image als GitHub-Release                         |
| Manuell (Actions → Build image → Run workflow)      | mit Version, wahlweise als Release               |

Die Release-Notizen nennen den Commit, das GSI, die App-Version und die Prüfsummen.

## Neue Version veröffentlichen

1. Änderungen in `src/` oder `build/sources.json` per Pull Request einbringen. Der Workflow baut das Image zur Probe.
2. Nach dem Merge den Tag setzen:

```bash
git tag v9
git push origin v9
```

3. Ist das Release fertig, `IMAGE_VERSION` in `flash.sh` auf die neue Version setzen.

> [!TIP]
> Für eine neue Version der Home-Assistant-App reicht es, `version`, `url` und `sha256` in `build/sources.json` zu
> ändern.
