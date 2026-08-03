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

The repo is private, so authenticate git first (either `gh auth login`, or
add an SSH key to GitHub):

```sh
git clone git@github.com:Soos3D/x-openclaw.git ~/x-openclaw
cd ~/x-openclaw && ./scripts/setup.sh --check   # see what the box is missing
./scripts/setup.sh                              # installs skill + xurl; STOP at the model-auth prompt
```

Ctrl-C when it reaches the model auth step — those credentials migrate from
the laptop instead (`setup-token` wants a browser the server doesn't have).

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
cd ~/x-openclaw
./scripts/migrate-state.sh import ~/x-poster-state-*.tar.gz
xurl /2/users/me            # must print your handle
openclaw models status      # must show the anthropic profile
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
cd ~/x-openclaw && git pull && ./scripts/install.sh   # state/ is never touched
```

If the persistent Telegram session ignores an update, send `/new` to the
bot — sessions only re-read config and skill files when they start.
