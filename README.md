# Running Dreeve on Podman

Instructions to run [Dreeve](https://github.com/dreeveapp/dreeve) with Podman,
using the public image
[`robiningelbrecht/dreeve`](https://hub.docker.com/r/robiningelbrecht/dreeve).

There are two ways to run it:

- **[Quadlet (recommended)](#always-on-setup-with-quadlet)** — an
  always-on, rootless systemd setup that runs both the **web** container and
  the **daemon** container, so imports, automation-rule backfill, render-cache
  pruning and notifications all happen on their own. Linux + systemd only.
- **[Simple single-container scripts](#simple-single-container-setup)** — a
  minimal, self-contained "try it out" setup: one container, a few shell
  scripts, no daemon. Great for kicking the tyres or running on Windows/macOS,
  but recurring tasks must be run by hand. See its
  [limitations](#limitations).

Pick Quadlet for a real install; pick the scripts to try Dreeve quickly.

## Files

| File                  | Purpose                                                       |
| --------------------- | ------------------------------------------------------------- |
| `dreeve.env.example`  | Environment template. Copy to `dreeve.env` and edit.          |
| `quadlet/`            | Quadlet units for the always-on web + daemon setup.           |
| `run.sh`              | (Simple setup) Pulls the image and starts one container.      |
| `import.sh`           | (Simple setup) Runs `bin/console app:import:files`.           |
| `ctl.sh`              | (Simple setup) Helpers: logs, shell, console, status, etc.    |

## Prerequisites

- [Podman](https://podman.io/) installed and on your `PATH`.
- For the Quadlet setup: a **Linux** host with **systemd** (Podman 4.4+).

## Always-on setup with Quadlet

This is the recommended setup.

Quadlet is systemd integration for Podman, so
this path is **Linux + systemd only**.  
The units are **rootless**: they run as your user and store data under `~/dreeve`.

It runs two containers from the same image:

- **web** (`dreeve`) — serves the UI and owns database migrations.
- **daemon** (`dreeve-daemon`) — runs the recurring background tasks.

### 1. Create the data directory and env file

```bash
mkdir -p ~/dreeve/storage/database ~/dreeve/storage/files ~/dreeve/storage/gear-maintenance ~/dreeve/build ~/dreeve/watch
cp dreeve.env.example ~/dreeve/dreeve.env
vi ~/dreeve/dreeve.env
```

Edit `~/dreeve/dreeve.env`: 

- set `APP_SECRET` to the output of `openssl rand -hex 32`
- set `ADMIN_USERNAME`
- leave `ADMIN_PASSWORD_HASH` blank for now (you generate it in step 3)
- set `APP_URL` to the URL you reach the app on, including the port
  (default `http://localhost:8081`)

### 2. Install and start the units

```bash
mkdir -p ~/.config/containers/systemd
cp quadlet/dreeve.container quadlet/dreeve-daemon.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start dreeve.service dreeve-daemon.service
```

To keep the services running after you log out and start them on boot:

```bash
loginctl enable-linger "$USER"
```
This need to be done only once per user,
if you already use Quadlets, you've probably already done it.

### 3. Set the admin password

The hash command runs inside the running container, so do this after step 2:

```bash
podman exec -it dreeve bin/console security:hash-password
```

Copy the resulting bcrypt hash into `ADMIN_PASSWORD_HASH` in
`~/dreeve/dreeve.env`, **raw** (no quotes, no escaping):

```
ADMIN_PASSWORD_HASH=$2y$13$bHxkUSQsfOt1T.dqbu8g4u/H6EXruv.lPUrwi.4NEGdkrKslTDAqW
```

Then restart so the containers pick up the change:

```bash
systemctl --user restart dreeve.service dreeve-daemon.service
```

### Managing and customizing

```bash
systemctl --user status dreeve.service dreeve-daemon.service
journalctl --user -u dreeve.service -f          # follow web logs
journalctl --user -u dreeve-daemon.service -f   # follow daemon logs
systemctl --user stop dreeve-daemon.service dreeve.service
```

The units default to `127.0.0.1:8081` and `~/dreeve`. To change the port,
image or data location, edit the `PublishPort=`, `Image=` and
`Volume=`/`EnvironmentFile=` lines in the two `.container` files (`%h` is your
home directory), then run `systemctl --user daemon-reload` and restart the
services.  
Keep `APP_URL` in `~/dreeve/dreeve.env` in sync with the published
port, and make sure **both** units always mount the same volumes.

Migrations run automatically whenever the web container starts, so pulling a
newer image and restarting upgrades the schema.

## Exposing the app to the internet

This applies to both setups. This is an optional step, be aware:
**Dreeve does not authenticate read access.**

Only `/admin` (login) and the `/api` endpoints require credentials.
The dashboard and all of your activity data (routes, maps, stats)
are served publicly. Exposing the app to the internet means anyone with the
URL can see that data. Only expose it if you are comfortable with your
activities and location infos being public, or put your own authentication
(for example HTTP basic auth) in front of it at the reverse proxy.

By default the container only listens on the local host port `8081`. To reach
it from the internet with a domain name and HTTPS, run a reverse proxy on the
host in front of that port. Pick either Caddy or nginx below.

The `APP_URL` setting must match your public address when using a proxy.
For example set `APP_URL=https://dreeve.example.com`, then restart the
service(s).

### Option A — Caddy (automatic HTTPS)

Caddy obtains and renews Let's Encrypt certificates automatically. Install
Caddy on the host, then use this `Caddyfile`:

```caddyfile
dreeve.example.com {
    # Protect the publicly-exposed app with HTTP basic auth:
    basic_auth {
        # <username>  <bcrypt hash from "caddy hash-password">
        myuser $2a$14$Zkx19XLiW6VYouLHR5NmfOFU0z2GTNmpkT/5qqR7hx4IjWJPDhjvG
    }

    reverse_proxy 127.0.0.1:8081
}
```

Replace `dreeve.example.com` with your domain and `8081` with your port if you
changed it. Generate a password hash and drop it into the `basic_auth` block
(replace `myuser` and the hash):

```bash
caddy hash-password
```

Then reload Caddy:

```bash
sudo caddy reload --config /etc/caddy/Caddyfile
```

### Option B — nginx (with Let's Encrypt via certbot)

Install nginx and certbot on the host. Create
`/etc/nginx/sites-available/dreeve.conf`:

```nginx
server {
    listen 80;
    server_name dreeve.example.com;

    location / {
        # Protect the publicly-exposed app with HTTP basic auth
        auth_basic           "Dreeve";  # HTTP Realm
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass         http://127.0.0.1:8081;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

Replace `dreeve.example.com` with your domain and `8081` with your port if you
changed it. Create the password file referenced by `auth_basic_user_file`
(the `-c` flag creates the file, omit it to add more users later;
`htpasswd` ships with the `apache2-utils` / `httpd-tools` package):

```bash
sudo htpasswd -c /etc/nginx/.htpasswd myuser
```

Then enable the site and reload, then obtain a certificate (certbot rewrites
the config to add the HTTPS server block and a redirect):

```bash
sudo ln -s /etc/nginx/sites-available/dreeve.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d dreeve.example.com
```

## Importing activity files

Put your activity files (`.fit`, `.gpx`, `.tcx`) into the `watch/` directory
inside your data root (`~/dreeve/watch` for the Quadlet setup, `./watch` for
the simple setup).

- **Quadlet setup:** the daemon imports them automatically every 5 minutes.  
  To import immediately run: `podman exec -it dreeve bin/console app:import:files`.
- **Simple setup:** run `./import.sh` (there is no daemon).

Importing requires `IMPORT_MODE=files`.  
Under `IMPORT_MODE=stravaApi` the file
import exits early without importing.

## Data and persistence

These directories under your data root (`~/dreeve` for Quadlet, the repo folder
or `DREEVE_DATA_ROOT` for the simple setup) are bind-mounted so data survives
restarts and image re-pulls:

| Host path            | Container path                | Holds                      |
| -------------------- | ----------------------------- | -------------------------- |
| `storage/database`   | `/var/www/storage/database`   | SQLite database            |
| `storage/files`      | `/var/www/storage/files`      | Imported/generated files   |
| `storage/gear-maintenance` | `/var/www/storage/gear-maintenance` | Gear-maintenance config/images |
| `build`              | `/var/www/build`              | Render cache               |
| `watch`              | `/var/www/watch`              | Drop-zone for import files |

## Simple single-container setup

This is the lightweight alternative: a self-contained set of shell scripts that
run Dreeve as **one** Podman container, with **no daemon**. Everything you need
is in this folder, so you can copy it anywhere and run it. Persistent data lives
next to the scripts by default (override with `DREEVE_DATA_ROOT`).

Use it to try Dreeve out, or where systemd/Quadlet is not available. Recurring
tasks do not run on their own here — see [Limitations](#limitations).

### Quick start

Clone the project and create your env file:

```bash
git clone https://github.com/timendum/dreeve-podman.git
cd dreeve-podman
cp dreeve.env.example dreeve.env
vi dreeve.env
```

Edit `dreeve.env`:

- set `APP_SECRET` to the output of `openssl rand -hex 32`
- set `ADMIN_USERNAME`
- leave `ADMIN_PASSWORD_HASH` blank for now
- set `APP_URL` to the URL you reach the app on, including the port

Pull the image and start the container:

```bash
./run.sh
```

Generate the admin password hash (needs the container running):

```bash
./ctl.sh console security:hash-password
```

Copy the resulting bcrypt hash into `ADMIN_PASSWORD_HASH` in `dreeve.env`,
**raw** (no quotes, no escaping):

```
ADMIN_PASSWORD_HASH=$2y$13$bHxkUSQsfOt1T.dqbu8g4u/H6EXruv.lPUrwi.4NEGdkrKslTDAqW
```

Then recreate the container to apply the change:

```bash
./run.sh
```

### Limitations

The simple setup deliberately leaves out Dreeve's background **daemon**, so the
following do **not** happen automatically:

- **File import** — run it yourself with `./import.sh`.
- **Automation-rule backfill** — rules you create are not applied to existing
  activities on their own.
- **Render-cache pruning** — the `build/` cache is not trimmed over time.
- **Notifications** — gear-maintenance-due and app-update-available
  notifications are never sent.

You can run any of these by hand via `./ctl.sh console <command>` (for example
`./ctl.sh console app:cache:render:prune`). If you want them to run on their
own, use the [Quadlet setup](#always-on-setup-with-quadlet) instead.

### Everyday commands

```bash
./ctl.sh status     # is it running?
./ctl.sh logs -f    # follow logs
./ctl.sh shell      # shell inside the container
./import.sh         # import activity files from ./watch now
./ctl.sh restart    # restart (does NOT reload dreeve.env; use ./run.sh for that)
./run.sh            # recreate the container and apply dreeve.env changes
./ctl.sh stop       # stop (container kept)
./ctl.sh rm         # remove container (data kept on host)
```

### Configuration overrides

All scripts honor these environment variables:

| Variable            | Default                                      | Meaning                          |
| ------------------- | -------------------------------------------- | -------------------------------- |
| `DREEVE_CONTAINER`  | `dreeve`                                     | Container name                   |
| `DREEVE_IMAGE`      | `docker.io/robiningelbrecht/dreeve:latest`   | Image to pull/run                |
| `DREEVE_PORT`       | `8081`                                       | Host port mapped to container 8080 |
| `DREEVE_ENV_FILE`   | `./dreeve.env`                               | Env file passed to the container |
| `DREEVE_DATA_ROOT`  | this folder                                  | Base dir for the bind mounts     |

Example — run a pinned version on a different port:

```bash
DREEVE_IMAGE=docker.io/robiningelbrecht/dreeve:v1.2.3 DREEVE_PORT=9000 ./run.sh
```

When you change the port this way, set `APP_URL=http://localhost:9000` in
`dreeve.env` to match, then re-run `./run.sh` so the container picks it up.
Otherwise Dreeve keeps generating links for the old port.
