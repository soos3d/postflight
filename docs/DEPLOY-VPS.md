# Deploying to a VPS

The skill is built for this: API posting plus Telegram approvals means no
display server anywhere. Any 1–2 GB Ubuntu 24.04 box works (Hetzner CX22,
DigitalOcean, Vultr — x86_64 or arm64, both have Node and xurl builds).

The one rule that matters: **never have the laptop and the server live at the
same time.** Two gateways fight over the same Telegram bot's updates, and two
cron sets double-post — the daily cap is per-machine state. Follow the order
below; the laptop goes dark before the server goes live.

## 1. Provision and harden (~10 min)

Create the box with SSH key auth, then:

```sh
adduser poster && usermod -aG sudo poster
rsync -a ~/.ssh /home/poster/ && chown -R poster:poster /home/poster/.ssh
ufw allow OpenSSH && ufw enable          # everything the skill does is outbound
apt update && apt install -y unattended-upgrades git jq rsync curl
```

Optional but worth it: install `vhs` and/or `freeze` (Linux release
binaries on their GitHub pages) so repo posts get their demo media —
generation is headless-safe. Without them the skill degrades to text-only
posts (CONTENT.md "Media recipes").

Log back in as `poster` for everything below. Optional but recommended:
disable root login and password auth in `/etc/ssh/sshd_config`.

## 2. Node and OpenClaw

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
exec $SHELL
nvm install 24
npm install -g openclaw
openclaw onboard        # accept defaults; creates ~/.openclaw + workspace
```

## 3. Clone and install the skill

```sh
git clone https://github.com/Soos3D/x-poster.git ~/x-poster
cd ~/x-poster && ./scripts/setup.sh --check   # see what the box is missing
./scripts/setup.sh                              # installs skill + xurl; STOP at the model-auth prompt
```

Ctrl-C when it reaches the model auth step — those credentials migrate from
the laptop instead (`setup-token` wants a browser the server doesn't have).
Exception: on the ChatGPT/Codex path the wizard uses a device-code flow on
headless boxes (it prints a URL + one-time code you approve from any
browser), so OpenAI users can finish model auth directly on the server and
skip that part of the migration. xurl tokens and skill state still migrate
either way.

## 4. Migrate credentials and state from the laptop

On the **laptop** (stop the gateway first so the auth store isn't copied
mid-write):

```sh
openclaw gateway stop
./scripts/migrate-state.sh export
scp ~/x-poster-state-*.tar.gz poster@SERVER:
```

On the **server**:

```sh
cd ~/x-poster
./scripts/migrate-state.sh import ~/x-poster-state-*.tar.gz
xurl /2/users/me            # must print your handle
openclaw models status      # must show your provider profile (anthropic or openai)
rm ~/x-poster-state-*.tar.gz
```

Delete the tarball on the laptop too. If either check fails, fix it before
going further — nothing is live yet on either machine.

## 5. Telegram + gateway on the server

Rotate the bot token first (@BotFather → /token → regenerate) so the old,
possibly-exposed one dies with the laptop install. Then rerun the wizard —
it now skips everything done above and picks up at Telegram:

```sh
./scripts/setup.sh
```

Enter the new token; pairing runs again (message the bot, paste the code).
`openclaw gateway install` runs inside that step and registers a systemd
user service on Linux. Make it survive logout and reboots:

```sh
sudo loginctl enable-linger poster
openclaw gateway status && openclaw doctor
```

Codex-subscription installs: run plain `openclaw doctor` freely, but treat
`doctor --fix` with care — released versions have rewritten subscription
model routes to API-billed ones (openclaw#79461). After any `--fix`, confirm
`openclaw models status` still shows a subscription model (`gpt-5.6-sol` /
`-terra`), not plain `openai/gpt-5.6`.

## 6. Verify, then cut over

With the laptop gateway still **stopped**:

1. Message the bot: `x-poster: draft a post`. The draft must come from the
   server. Reply `skip` and check `state/skipped/` on the server.
2. Run one full `ship` round trip; confirm the permalink and the post-log
   entry on the server.

Only after both pass, retire the laptop copy — on the **laptop**:

```sh
openclaw cron list                       # note the four x-poster job ids
openclaw cron rm <id>                    # all four
openclaw gateway uninstall               # LaunchAgent gone for good
```

The server's cron step in `setup.sh` already registered the four jobs (it
prompts for slot times; the defaults target US engagement windows and stay
DST-correct via `--tz America/New_York`). Watch the next slot fire
unattended.

## 7. Monitoring

Cron failures already alert to Telegram. Add a weekly heartbeat so silence
itself becomes a signal — if the Monday message doesn't arrive, the gateway
is down:

```sh
openclaw cron create "0 9 * * 1" \
  "Run 'openclaw doctor' via shell and send me a one-line health summary, mentioning xurl and model auth status." \
  --name x-poster-doctor --session isolated --tz America/New_York \
  --channel telegram --to YOUR_TELEGRAM_USER_ID
```

## 8. Updating the skill later

The laptop is the dev machine; the server only consumes git:

```sh
# laptop: edit, commit, push
# server:
cd ~/x-poster && git pull && ./scripts/install.sh   # state/ is never touched
```

If the persistent Telegram session ignores an update, send `/new` to the
bot — sessions only re-read config and skill files when they start.
