# New API for Homebrew

Apple Silicon macOS tap for [QuantumNous/new-api](https://github.com/QuantumNous/new-api). It runs the Go server with SQLite, an embedded web console, and a per-user `launchd` service.

## Install and start

```sh
brew tap KaranocaVe/new-api
brew trust --formula KaranocaVe/new-api/new-api
brew install KaranocaVe/new-api/new-api
new-api-init
brew services start new-api
open http://localhost:3000
```

`new-api-init` creates a private configuration file on first use. Starting the service also initializes it when needed. On the first visit, New API opens its `/setup` wizard; create the administrator username and a strong password there. A fresh SQLite database has no default account or shared password.

The Homebrew service runs as your user, starts at login, and is restarted by `launchd` after an unexpected exit. It needs no root privileges, Docker, database daemon, Redis, Node.js, or Electron. Go and Bun are build-only Homebrew dependencies; neither runs the service. The first source build downloads the frontend dependencies and can take several minutes.

## Network binding

Upstream currently constructs its HTTP address as `":" + PORT`, which listens on every interface. The Formula applies a small source patch that adds `BIND_ADDRESS` and defaults it to `127.0.0.1`; the optional pprof listener uses the same address. The updater checks the patch by building the Formula in macOS CI. Do not set `BIND_ADDRESS=0.0.0.0` unless you intend to expose the gateway to the network.

The service listens on port `3000` by default. Edit the private environment file to change it:

```sh
${EDITOR:-nano} "$(brew --prefix)/var/new-api/.env"
brew services restart new-api
```

Set `PORT=3001` for a different port. Keep `BIND_ADDRESS=127.0.0.1` for local-only access. The stock upstream release binary is not used because it cannot enforce this bind address.

## Files and permissions

All mutable state lives outside the versioned Cellar directory, so upgrades and service restarts retain it:

```text
$(brew --prefix)/var/new-api/
├── .env                 # mode 0600; includes a generated 256-bit SESSION_SECRET
├── data/new-api.db      # SQLite database; WAL/SHM files stay beside it
└── logs/
    ├── stdout.log       # launchd output
    ├── stderr.log       # launchd errors
    └── oneapi-*.log     # New API application logs
```

The `.env` is loaded from the service working directory. The Formula sets `SQLITE_PATH` to the stable `data/new-api.db` path and includes upstream's `busy_timeout(30000)`, `journal_mode(WAL)`, and `txlock=immediate` SQLite options; the upstream fallback filename is `one-api.db`. `SQL_DSN` and `REDIS_CONN_STRING` remain unset, which selects SQLite and disables Redis. The embedded frontend needs no separate web server. The application may use the OS temporary directory for transient request/body data; it is not the database backup location.

## Upgrade and database changes

```sh
brew update
brew upgrade new-api
brew services restart new-api
```

New API migrates the SQLite schema during startup. Back up the stopped service before an upgrade. A downgrade may not understand a schema already migrated by a newer release; restore the matching pre-upgrade database and `.env` instead of pointing an older binary at the newer database.

The updater considers published `vMAJOR.MINOR.PATCH` stable tags and `vMAJOR.MINOR.PATCH-rc.N` tags, excludes drafts and alpha/beta tags, and picks the highest SemVer version that has an exact `new-api-macos-<tag>` asset. RC tags are included deliberately because upstream currently publishes its `1.0.0-rc.N` line as ordinary Releases; GitHub's `prerelease` flag alone is not reliable for that line. A future `1.0.0` stable release sorts above `1.0.0-rc.N`. Newer supported releases without a macOS asset are reported and skipped so they do not break the scheduled check or get confused with Linux ARM64 builds. Before opening or updating a pull request, the workflow verifies the selected asset's release checksum, Mach-O format, and arm64 architecture, then hashes and builds the source archive. It never updates `main` directly.

At the initial pin, the verified upstream macOS asset is `new-api-macos-v1.0.0-rc.47` with SHA-256 `f5859a8a18d07b13d7fdd7b175416e221e73d494056dd7643999ba30a846f391`. The Formula instead pins the corresponding source archive (SHA-256 `6e718051ca5c753005be9378425517523c49fe4d6345b572efa822a24dfea391`) and compiles it locally with the localhost patch. The source build is slower and uses Go/Bun build dependencies, but the resulting service has a real loopback bind. The release's Mach-O is arm64 and ad-hoc signed; upstream does not notarize it. The Tap does not remove quarantine attributes or weaken macOS security settings.

## Backup and restore

Stop New API before copying SQLite so the database and any WAL state are consistent:

```sh
brew services stop new-api
ditto "$(brew --prefix)/var/new-api" "$HOME/new-api-backup"
brew services start new-api
```

To restore, stop the service, preserve the current state under a different name, then copy the backup into place:

```sh
brew services stop new-api
state="$(brew --prefix)/var/new-api"
mv "$state" "$state.before-restore"
ditto "$HOME/new-api-backup" "$state"
chmod 700 "$state" "$state/data" "$state/logs"
chmod 600 "$state/.env"
brew services start new-api
```

`brew uninstall new-api` removes the Formula but does not remove `$(brew --prefix)/var/new-api`. Delete that directory yourself only after making any needed backup.

## Troubleshooting

- Check service state with `brew services list`; stop/start with `brew services stop new-api` and `brew services start new-api`.
- Read launchd output at `$(brew --prefix)/var/new-api/logs/stdout.log` and `stderr.log`; application logs are in the same `logs` directory.
- If port 3000 is occupied, set a free numeric `PORT` in `.env`, then restart.
- If the database is unexpectedly empty, confirm `.env` still has the absolute `SQLITE_PATH` under `$(brew --prefix)/var/new-api/data`.
- If an update fails to build, the upstream source may have changed the bind/listener code; the automation will not open a PR until the Formula patch and macOS checks pass.

## Upstream references

- [Release workflow](https://github.com/QuantumNous/new-api/blob/main/.github/workflows/release.yml)
- [Server startup and listener](https://github.com/QuantumNous/new-api/blob/main/main.go)
- [Environment loading and SQLite configuration](https://github.com/QuantumNous/new-api/blob/main/common/init.go)
- [SQLite DSN and WAL defaults](https://github.com/QuantumNous/new-api/blob/main/common/database.go)
