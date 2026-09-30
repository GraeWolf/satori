# Tekne branding

Source artwork for the `tekne-branding` package, which renders it to PNG at
build time (`packages/tekne-branding/debian/rules`). Licensed CC-BY-SA-4.0
(DEC-019, DEC-034; full text in [LICENSE](LICENSE)), unlike the rest of the
repository.

These are **placeholders**: a geometric T in a ring (Tekne is Greek for craft) on Tokyo Night
colours. They contain no text, so rendering needs no fonts. Replace a file
with real artwork of the same name and size and the build picks it up.

| File | Size | Used for |
|---|---|---|
| `logo.svg` | 512×512 | Logo (`/usr/share/tekne/branding/`) |
| `wallpaper.svg` | 3840×2160 | Desktop wallpaper (`/usr/share/backgrounds/tekne/tekne.png`) |
| `grub-background.svg` | 1920×1080 | GRUB theme background, live ISO and installed systems |

Palette: Tokyo Night (night). Background `#1a1b26`, dark `#16161e`,
foreground `#c0caf5`, blue `#7aa2f7`, magenta `#bb9af7`, comment `#565f89`.
