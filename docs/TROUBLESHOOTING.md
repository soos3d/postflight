# Troubleshooting

Symptoms first. Find yours, apply the fix.

Before anything else, run the health check — it inspects every layer and
changes nothing:

```sh
./scripts/setup.sh --check
```

## The bot ignores a change I just made

You edited a skill file, or changed the model, and the bot behaves as
before.

**Send `/new` to the bot.** The persistent Telegram session reads config
and skill files only when it starts, so a running session keeps the old
copy until you reset it.

If the edit was to a tracked file in your git checkout, that alone isn't
enough — a default install *copies* the skill to
`~/.openclaw/workspace/skills/postflight/`. Rerun `./scripts/install.sh`
first, then send `/new`. To skip this loop entirely, install once with
`./scripts/install.sh --dev`, which symlinks the checkout instead.

## X API: `client-not-enrolled`

Auth succeeds, then every v2 call fails.

Your app is standalone. At [console.x.com](https://console.x.com/) an app
must live **inside a project**, and the project must be on a package with
write access. Create a project, create the app inside it, then redo the
`xurl` auth steps.

## X API: media upload rejected

The OAuth token predates the `media.write` scope. Rerun the consent flow:

```sh
xurl auth oauth2 --app postflight
```

## A cron job never fires

The job exists in `openclaw cron list` but nothing arrives.

Cron delivery defaults to `announce -> last`, which has no route in an
isolated session and fails closed. Every job needs an explicit route:

```sh
--channel telegram --to YOUR_TELEGRAM_USER_ID
```

`setup.sh` does this for you. Recreate the job by hand and it's the easiest
thing to forget.

## Cron fires, but the drafts ignore my pillars

Your jobs were created before the pillar system and still carry old
per-topic messages.

```sh
./scripts/setup.sh
```

The wizard detects the drift and recreates the jobs in place, keeping the
same schedule and route. You can also delete and recreate them by hand.

Current messages are slot-numbered and pillar-agnostic ("slot 1 of the
pillar schedule"), so rescheduling never means editing cron messages again.

## My OpenAI bill went up

`openclaw doctor --fix` has rewritten Codex-subscription routes to
API-billed ones in released versions ([openclaw#79461](https://github.com/openclaw/openclaw/issues/79461)).

Plain `openclaw doctor` is safe to run freely. After any `--fix`, check:

```sh
openclaw models status
```

It must show a subscription model — `openai/gpt-5.6-sol` or
`openai/gpt-5.6-terra`. Plain `openai/gpt-5.6` is the API-key alias and
silently bills a developer account instead of your subscription. Never set
it directly either.

## The slots stopped drafting mid-week

Most likely the primary model's usage pool is spent. Fable 5 has its own
allowance, separate from the rest of the Claude subscription, and a cron slot
that hits the limit dies inside OpenClaw — nothing in the skill can catch it.

Check whether a fallback chain exists:

```sh
openclaw models status
```

If `fallbacks` is empty, add one. There's still Opus budget on the account
when Fable runs out, so the slot drafts instead of failing:

```sh
openclaw models list --provider anthropic     # confirm the ids in your release
openclaw config set agents.defaults.model.fallbacks \
  '["anthropic/claude-opus-4-8","anthropic/claude-sonnet-5"]' --strict-json
```

`./scripts/setup.sh` does this for you, and leaves an existing chain alone.

> `config set` accepts a model id that doesn't exist in your OpenClaw
> release — no error at write time, just a dead cron run later. Always check
> `models list` first.

Cron slots run in isolated sessions and pick the chain up on their next run.
The Telegram chat session pins its model config when it's created, so send
`/new` to the bot for the change to reach it.

## Drafts sound generic

Two likely causes, in order:

1. **No `voice-examples.local.md`.** Your own tweets outrank every other
   style rule. Without them the output is fluent and anonymous. See
   [CUSTOMIZE.md](CUSTOMIZE.md#2-your-voice).
2. **A small model.** Local 7B-class models write exactly the slop
   `VOICE.md` bans. Check `openclaw models status` points at a frontier
   model.

## My pillar edits do nothing

`pillars.local.md` still has its `TEMPLATE` line at the top. The skill
ignores the file while that line is present, so an unedited copy can never
drive posting. Delete the line.

Also check you replaced the `## Pillars` and `## Weekly grid` sections
*completely* — they override the defaults wholesale rather than merging, so
a partial list silently shrinks your schedule.

## Renaming a pillar reset its history

Expected. Past posts are keyed by pillar name in the post log, so a rename
starts the rotation fresh.

## Nothing sends; drafts pile up in `state/drafts.md`

`telegramTo` is empty in `state/settings.json`. That's draft mode, and it's
the safe default: the skill writes drafts to disk, sends nothing, posts
nothing. Set your Telegram user id to go live.

## `openclaw skills list` doesn't show postflight as ready

On a `--dev` install, the symlink target must be trusted via
`skills.load.allowSymlinkTargets` in `~/.openclaw/openclaw.json`. The
installer prints the exact snippet to paste.

## Telegram photo lands without a taken date

You sent it as a photo. Telegram recompresses photo-sends and strips the
date the library needs.

**Attach → File.** The bot asks you to resend when it detects this.

## Telegram photo refused: HEIC

X doesn't accept HEIC. Convert it first:

```sh
sips -s format jpeg IMG_4132.heic --out IMG_4132.jpg   # macOS
```

To stop it recurring, set the iPhone camera to shoot JPEG:
Settings → Camera → Formats → **Most Compatible**.

## Telegram album refused

One photo per message, each with its own caption. A shared album caption
can't say why each shot matters, and that note is what captions get drafted
from. To seed a real backlog, copy the files over and run
`./scripts/ingest-photo.sh` once per photo.

## Photo refused: over the size cap

X caps images at 5 MB.

```sh
sips -Z 2048 IMG_4132.jpg   # macOS
```

## Photo refused: no EXIF date

Pass it explicitly:

```sh
./scripts/ingest-photo.sh --taken 2026-06-14 photo.jpg "note" tag
```

## Photo refused: location metadata survived the strip

The script fails closed and does not add the photo — correct behavior, not
a bug. Check your `exiftool` install is current, and don't work around it by
editing the manifest by hand.

## A draft expired

Drafts expire after 24 hours. Ask for a new one.

## Both machines are posting

You have a laptop and a server live at once. Two gateways fight over the
same Telegram bot's updates, and two cron sets double-post because the
daily cap is per-machine state.

Retire one. [DEPLOY-VPS.md](DEPLOY-VPS.md) walks the cutover in the safe
order.

## I typed my client secret into the shell

`xurl` accepts the secret only as a flag, so it lands in shell history in
plaintext.

Delete the history line. If you suspect it leaked, rotate the secret at
[console.x.com](https://console.x.com/). To avoid it next time, prefix the
command with a space (`setopt HIST_IGNORE_SPACE` in zsh,
`HISTCONTROL=ignorespace` in bash), or let `setup.sh` prompt for it hidden.

## Auth expired

The agent stops and alerts you. By design it never attempts a login and
never touches credentials, so reauthorize by hand:

```sh
xurl auth oauth2 --app postflight        # X
openclaw models auth setup-token --provider anthropic   # Claude
openclaw models auth login --provider openai            # ChatGPT/Codex
```

## Still stuck

If something is broken, open an
[issue](https://github.com/soos3d/postflight/issues) with the output of
`./scripts/setup.sh --check` — it reports every layer and includes no secrets.
If it's a question rather than a bug, ask in
[Discussions](https://github.com/soos3d/postflight/discussions).
