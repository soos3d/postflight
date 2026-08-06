# Make it yours

Everything personal about an install lives in two untracked local files and
one settings key. Nothing here requires editing tracked files, so
`git pull` never conflicts with your customization and `install.sh` never
overwrites it.

1. [Your content pillars](#1-your-content-pillars)
2. [Your voice](#2-your-voice)
3. [Photo libraries](#3-photo-libraries)
4. [Style references](#4-style-references)
5. [Posting times](#5-posting-times)

## Where these files live

The default install **copies** the skill into
`~/.openclaw/workspace/skills/x-poster/`. That copy is what the agent
reads, so that's where these files belong.

`install.sh` never touches `state/` or any `*.local.md` file there. But
edits to *tracked* files in your checkout only take effect after rerunning
`./scripts/install.sh` — or install once with `--dev` to symlink the
checkout instead.

**After changing any of this, send `/new` to your bot.** The persistent
session re-reads files only when it starts.

## 1. Your content pillars

The skill ships a generic schedule: repo demos plus insights. To add your
own topics:

```sh
cd ~/.openclaw/workspace/skills/x-poster   # or the checkout, with --dev
cp pillars.example.md pillars.local.md
```

Then edit `pillars.local.md`:

- Replace the sketched personal pillars with topics you can write about
  firsthand
- Adjust the weekly grid
- **Delete the `TEMPLATE` line at the top.** The skill ignores the file
  while that line is present, so an unedited copy can never drive posting

The template explains the five pillar properties and the grid rules inline.

> **Two things people trip on.** Your `## Pillars` list and `## Weekly
> grid` replace the defaults *entirely*, so keep them complete rather than
> writing a diff. And renaming a pillar resets its rotation history,
> because past posts are keyed by pillar name in the post log.

A pillar with `media: photos:<dir>` draws from a photo library you curate.
Its grid cells fall back to another pillar until the library has photos in
it.

## 2. Your voice

`voice-examples.local.md` holds 3 to 5 of your own tweets, pasted verbatim.

They outrank every other style rule, so the account keeps sounding like
you. Don't skip this one. `VOICE.md` prevents machine-sounding output, but
only your own tweets make it sound like *you*.

## 3. Photo libraries

For pillars with `media: photos:<dir>`.

A photo library is a directory (typically `state/media/photos/`) plus a
`manifest.yaml` describing each photo:

| Field | What it's for |
|---|---|
| `tags` | Selection |
| `location` | Optional, shown in the approval message |
| `note` | One line on why the shot matters. This becomes the caption seed |
| `taken` | The date, used by the cooldown rules |

Only photos with a manifest entry are postable, so nothing lands in your
feed that you didn't deliberately add.

There are two ways in.

### From your computer

Requires `exiftool`.

```sh
./scripts/ingest-photo.sh --location "Ichetucknee Springs State Park" \
  ~/Pictures/IMG_4132.jpg "water was glass, 72F year-round" springs kayak
```

The script strips all metadata, GPS coordinates included, from the library
copy, files it under a clean date-based name, and appends the manifest
entry.

The taken date comes from EXIF. Pass `--taken YYYY-MM-DD` if the photo has
none.

### From your phone

Send the photo to your bot with a one-line caption. The caption becomes the
note, the agent suggests tags from looking at the shot, and it runs the
same ingest script with the same metadata strip.

Three rules:

- **Send it as a file** (attach → File), not as a photo. Telegram
  recompresses photo-sends and strips the taken date the library needs. The
  bot asks you to resend when that happens.
- **One photo per message**, each with its own note. Albums get refused,
  because a shared caption can't say why each shot matters.
- **HEIC gets refused** with a conversion hint. On iPhone, Settings →
  Camera → Formats → "Most Compatible" makes the camera shoot JPEG and the
  whole flow friction-free.

Caption lines like `tags: springs kayak`, `location: ...`, or
`taken: 2026-06-14` override what's detected.

Seeding a real backlog goes faster through the shell: copy the photos over
and run the script once per photo.

### Cooldowns

A photo never posts the same day it was taken, and rests 60 days after
being posted. Selection and caption rules live in `CONTENT.md` under "Photo
library".

### Two rules the script can't enforce

- Keep home-adjacent spots out of the library entirely.
- Post after leaving a location, never from it.

### Backups

The library lives under `state/`, so it's never committed. A plain
`cp -R` of the photos directory is a full backup.

`migrate-state.sh` carries it too when you migrate machines, but that
tarball also contains live credentials, so don't reach for it as a casual
photo backup.

## 4. Style references

In `state/settings.json`, `styleAccounts` lists public accounts whose
register gets studied during the weekly style refresh.

Patterns only, never opinions or phrasings, and they're never named in
posts. Local config, never committed.

## 5. Posting times

The three daily slots are cron jobs. The defaults target US engagement
windows.

Change them by rerunning `./scripts/setup.sh`, or directly:

```sh
openclaw cron edit
```

Cron messages are slot-numbered and pillar-agnostic ("slot 1 of the pillar
schedule"), so schedule changes never require touching your pillar config,
and vice versa.

---

Something not working? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
