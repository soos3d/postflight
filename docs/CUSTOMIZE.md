# Make it yours

Everything personal about an install lives in two untracked local files
and one settings key. Nothing here requires editing tracked files, so
`git pull` never conflicts with your customization and `install.sh` never
overwrites it.

One path detail first: the default install **copies** the skill into
`~/.openclaw/workspace/skills/x-poster/`, so that's where the agent reads
these files. `install.sh` never touches `state/` or any `*.local.md`
file there, but tracked-file edits in the checkout only take effect after
rerunning `./scripts/install.sh` — or install once with `--dev` to
symlink the checkout instead. After changing any of this, send `/new` to
your bot: the persistent session only re-reads files when it starts.

## 1. Your content pillars — `pillars.local.md`

The skill ships a generic schedule (repo demos + insights). To add your
own topics:

```sh
cd ~/.openclaw/workspace/skills/x-poster   # or the checkout, with --dev
cp pillars.example.md pillars.local.md
```

Edit `pillars.local.md`: replace the sketched personal pillars with
topics you can write about firsthand, adjust the weekly grid, and
**delete the TEMPLATE line at the top** — the skill ignores the file
while that line is present, so an unedited copy can never drive posting.

The template explains the five pillar properties and the grid rules
inline. Two things people trip on:

- Your `## Pillars` list and `## Weekly grid` replace the defaults
  entirely — keep them complete, don't write a diff.
- Renaming a pillar resets its rotation history (past posts are keyed by
  pillar name in the post log).

A pillar with `media: photos:<dir>` draws from a photo library you
curate — see the next section. Its grid cells simply fall back to
another pillar until the library has photos in it.

## 1b. Photo libraries — for `media: photos:<dir>` pillars

A photo library is a directory (typically `state/media/photos/`) plus a
`manifest.yaml` describing each photo: tags, an optional location, a
one-line `note` — your memory of why the shot matters, which becomes the
caption seed — and the taken date. Only photos with a manifest entry are
postable, so nothing lands in your feed that you didn't deliberately add.

Add photos with the ingest script (requires `exiftool`):

```sh
./scripts/ingest-photo.sh --location "Ichetucknee Springs State Park" \
  ~/Pictures/IMG_4132.jpg "water was glass, 72F year-round" springs kayak
```

It strips all metadata — GPS coordinates included — from the library
copy, files it under a clean date-based name, and appends the manifest
entry. The taken date comes from EXIF (pass `--taken YYYY-MM-DD` if the
photo has none) and enforces the never-same-day rule; a photo also rests
60 days after being posted. Selection and caption rules live in
CONTENT.md "Photo library".

Two rules the script can't enforce: keep home-adjacent spots out of the
library entirely, and post after leaving a location, never from it. The
library lives under `state/`, so it is never committed; a plain `cp -R`
of the photos directory is a full backup (`migrate-state.sh` carries it
too when you migrate machines — but that tarball also contains live
credentials, so don't reach for it as a casual photo backup).

## 2. Your voice — `voice-examples.local.md`

3 to 5 of your own tweets, pasted verbatim. They outrank every other
style rule, so the account keeps sounding like you. Don't skip this one;
`VOICE.md` prevents machine-sounding output, but only your own tweets
make it sound like *you*.

## 3. Style references — `styleAccounts`

In `state/settings.json`, list public accounts whose register gets
studied during the weekly style refresh: patterns only, never opinions or
phrasings, and they're never named in posts. Local config, never
committed.

## 4. Posting times

The three daily slots are cron jobs; the defaults target US engagement
windows. Change them by rerunning `./scripts/setup.sh` or directly with
`openclaw cron edit`. The cron messages are slot-numbered and
pillar-agnostic ("slot 1 of the pillar schedule"), so schedule changes
never require touching your pillar config, and vice versa.
