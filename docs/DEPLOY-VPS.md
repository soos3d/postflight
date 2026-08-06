# Deploying to a VPS

The skill is built for this. API posting plus Telegram approvals means no
display server anywhere.

Any 1–2 GB Ubuntu 24.04 box works: Hetzner CX22, DigitalOcean, Vultr, on
x86_64 or arm64. Both architectures have Node and xurl builds.

> **The one rule that matters: never have the laptop and the server live at
> the same time.** Two gateways fight over the same Telegram bot's updates,
> and two cron sets double-post, because the daily cap is per-machine
> state.
>
> Follow the order below. The laptop goes dark before the server goes live.

Eight steps:

1. [Provision and harden](#1-provision-and-harden)
2. [Install Node and OpenClaw](#2-install-node-and-openclaw)
3. [Clone and install the skill](#3-clone-and-install-the-skill)
4. [Migrate credentials from the laptop](#4-migrate-credentials-from-the-laptop)
5. [Set up Telegram on the server](#5-set-up-telegram-on-the-server)
6. [Verify, then cut over](#6-verify-then-cut-over)
7. [Add monitoring](#7-add-monitoring)
8. [Updating later](#8-updating-later)

---

## 1. Provision and harden

About 10 minutes. Create the box with SSH key auth, then:

```sh
adduser poster && usermod -aG sudo poster
rsync -a ~/.ssh /home/poster/ && chown -R poster:poster /home/poster/.ssh
ufw allow OpenSSH && ufw enable          # everything the skill does is outbound
apt update && apt install -y unattended-upgrades git jq rsync curl python3
```

`setup.sh` refuses to continue without `git`, `curl`, `jq`, `rsync`, and
`python3`. That last one is easy to miss on a minimal image: it runs X's
character weighting on every draft.

Log back in as `poster` for everything below.

Recommended while you're here: disable root login and password auth in
`/etc/ssh/sshd_config`.

Also install the [`gh` CLI](https://cli.github.com/) and run `gh auth login`
as `poster`. It is how `source: repos` pillars read your repos; without it
`setup.sh` reports a todo rather than failing, and those slots fall back every
turn.

Optional but worth it — install `vhs` and/or `freeze` (Linux release
binaries on their GitHub pages) so repo posts get their demo media.
Generation is headless-safe. Without them the skill degrades to text-only
posts (`CONTENT.md`, "Media recipes").

## 2. Install Node and OpenClaw

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
exec $SHELL
nvm install 24
npm install -g openclaw
openclaw onboard        # accept defaults; creates ~/.openclaw + workspace
```

## 3. Clone and install the skill

```sh
git clone https://github.com/soos3d/postflight.git ~/postflight
cd ~/postflight
./scripts/setup.sh --check   # see what the box is missing
./scripts/setup.sh           # installs skill + xurl
```

**Ctrl-C when it reaches the model auth step.** Those credentials migrate
from the laptop instead, because `setup-token` wants a browser the server
doesn't have.

> **Exception for ChatGPT/Codex users.** On headless boxes the wizard uses
> a device-code flow, printing a URL and one-time code you approve from any
> browser. You can finish model auth directly on the server and skip that
> part of the migration. xurl tokens and skill state still migrate either
> way.

## 4. Migrate credentials from the laptop

On the **laptop**, stop the gateway first so the auth store isn't copied
mid-write:

```sh
openclaw gateway stop
./scripts/migrate-state.sh export
scp ~/postflight-state-*.tar.gz poster@SERVER:
```

On the **server**:

```sh
cd ~/postflight
./scripts/migrate-state.sh import ~/postflight-state-*.tar.gz
xurl /2/users/me            # must print your handle
openclaw models status      # must show your provider profile
rm ~/postflight-state-*.tar.gz
```

Delete the tarball on the laptop too — it contains live credentials.

If either check fails, fix it before going further. Nothing is live yet on
either machine.

## 5. Set up Telegram on the server

**Rotate the bot token first** (@BotFather → `/token` → regenerate), so the
old, possibly-exposed one dies with the laptop install.

Then rerun the wizard. It skips everything done above and picks up at
Telegram:

```sh
./scripts/setup.sh
```

Enter the new token. Pairing runs again: message the bot, paste the code.
`openclaw gateway install` runs inside that step and registers a systemd
user service.

Make it survive logout and reboots:

```sh
sudo loginctl enable-linger poster
openclaw gateway status && openclaw doctor
```

> **Codex-subscription installs:** run plain `openclaw doctor` freely, but
> treat `doctor --fix` with care. Released versions have rewritten
> subscription model routes to API-billed ones
> ([openclaw#79461](https://github.com/openclaw/openclaw/issues/79461)).
> After any `--fix`, confirm `openclaw models status` still shows a
> subscription model (`gpt-5.6-sol` or `-terra`), not plain
> `openai/gpt-5.6`.

## 6. Verify, then cut over

With the laptop gateway still **stopped**:

1. Message the bot `postflight: draft a post`. The draft must come from the
   server. Reply `skip` and check `state/skipped/` on the server.
2. Run one full `ship` round trip. Confirm the permalink and the post-log
   entry on the server.

Only after both pass, retire the laptop copy. On the **laptop**:

```sh
openclaw cron list                       # note the four postflight job ids
openclaw cron rm <id>                    # all four
openclaw gateway uninstall               # LaunchAgent gone for good
```

The server's cron step in `setup.sh` already registered the four jobs. It
prompts for slot times; the defaults target US engagement windows and stay
DST-correct via `--tz America/New_York`.

Watch the next slot fire unattended.

## 7. Add monitoring

Cron failures already alert to Telegram. Add a weekly heartbeat so silence
itself becomes a signal — if the Monday message doesn't arrive, the gateway
is down:

```sh
openclaw cron create "0 9 * * 1" \
  "Run 'openclaw doctor' via shell and send me a one-line health summary, mentioning xurl and model auth status." \
  --name postflight-doctor --session isolated --tz America/New_York \
  --channel telegram --to YOUR_TELEGRAM_USER_ID
```

## 8. Updating later

The laptop is the dev machine. The server only consumes git:

```sh
# laptop: edit, commit, push
# server:
cd ~/postflight && git pull && ./scripts/install.sh   # state/ and *.local.md are never touched
./scripts/setup.sh                                    # only if the release changed config
```

Then send `/new` to the bot. The persistent Telegram session reads the skill
files only when it starts, so it keeps the old copy until you reset it. Cron
slots run in isolated sessions and pick changes up on their next run.

`install.sh` only moves files. A release that changes OpenClaw *config* — the
model fallback chain in v1.1.0, for instance — lands through `setup.sh`, which
configures whatever is missing and leaves everything else alone. Release notes
say when it's needed; running it anyway is safe.

### Upgrading from x-poster

The skill was called x-poster before v1.0.0. Pulling that rename needs one
extra step, `setup.sh`, because the cron jobs carry the old name too:

> **This runs automatically until 2026-11-01.** After that the migration
> code comes out of `install.sh` and `setup.sh`. Upgrading a pre-v1.0.0
> install later still works, by hand: move `state/` and your `*.local.md`
> files from `skills/x-poster/` to `skills/postflight/`, delete the old
> directory, then delete and recreate the cron jobs (the commands are in
> [SETUP-MANUAL.md](SETUP-MANUAL.md#6-test-then-schedule)).

```sh
cd ~/postflight && git pull
./scripts/install.sh    # moves state/ and *.local.md to skills/postflight/
./scripts/setup.sh      # renames the cron jobs, keeping times and routes
openclaw cron list      # confirm the count is unchanged
```

`install.sh` moves the old skill directory to
`~/.openclaw/workspace/x-poster-pre-rename-backup/` rather than deleting it,
and leaves it there. Remove it once a draft loop has run.

Skipping `setup.sh` leaves cron jobs whose messages name a skill that no
longer exists, and drafting stops silently. Running it twice is safe.

Personal config (`pillars.local.md`, `voice-examples.local.md`) is
untracked, so it doesn't travel through git. It reaches a new box two ways:

- `migrate-state.sh`, which carries every `*.local.md`
- a plain `scp` into `~/.openclaw/workspace/skills/postflight/`

A photo library works the same way. It lives under `state/media/photos/`,
which `migrate-state.sh` carries with the rest of the state. It's the one
piece of state that keeps originating on your laptop, so `scp` new photos
over (or run `ingest-photo.sh` on the server) as you add them.

---

Something not working? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
