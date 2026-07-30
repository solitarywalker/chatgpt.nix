# chatgpt.nix

English | [日本語](./README_JP.md)

A Nix flake that packages
[evildevill/chatgpt-desktop-linux](https://github.com/evildevill/chatgpt-desktop-linux)
— an Electron window onto <https://chatgpt.com> — for NixOS.

Upstream ships a snap. This builds the same sources from the `v1.0.2` tag and
provides the wrapper, `.desktop` entry and icon instead.

## What the package does

There is no compile step. `src/main.js`, `src/preload.js` and `src/config/index.js`
are plain ESM that Electron runs as-is — upstream's `npm run dist:*` targets only
wrap them into a snap / AppImage / deb, which is the packaging this derivation
replaces. So the build fetches the dependency closure, puts the sources in the
store, and points an `electron` at them.

Only the 19 runtime packages are installed. `--omit=dev` drops electron,
electron-builder, eslint and prettier: this app has no bundler to run and no
linting to do at build time, and Electron itself comes from nixpkgs.

## Things upstream gets wrong, and what is done about them

| Problem | Handling |
|---|---|
| `package.json` and `package-lock.json` disagree on the electron version, so `npm ci` refuses to run | `package.json` is patched to match the lockfile |
| `main.js` looks for its window icon at `src/assets/icon.png`, but the file ships at `assets/icon.png` | a symlink is added at the path it asks for |
| `electron-context-menu` puts "Inspect Element" in the right-click menu of a release build | `ELECTRON_IS_DEV=0` is set by default |

### The lockfile mismatch

`docs/MESA-DRI-CRASH-FIX.md` describes downgrading Electron 40 → 33, and
`package.json` was duly changed to `^33.2.0` / `^25.1.8`. **The lockfile was never
regenerated** and still resolves electron 40.2.1 / electron-builder 26.7.0. npm
sees ranges the lockfile cannot satisfy, tries to re-resolve `electron` against the
registry, and fails as `ENOTCACHED` because a Nix build is offline.

`package.json` is aligned to the lockfile rather than the other way round: the
lockfile is what `npmDepsHash` is taken over, and `npmConfigHook` diffs it against
the cache's copy, so editing it would only trade this error for `npmDepsHash is out
of date`. Both packages are dropped by `--omit=dev` anyway, so the versions written
in are never installed — only the range check ever reads them.

The patch uses `--replace-fail`, so if upstream regenerates the lockfile this build
breaks loudly instead of quietly patching the wrong thing.

### The icon path

`main.js` builds the path as
`path.join(path.dirname(fileURLToPath(import.meta.url)), 'assets/icon.png')`, and
`import.meta.url` is `.../src/main.js`, so it resolves to `src/assets/icon.png`
while the file is at the repo root. Electron ignores a missing icon path silently,
which is why upstream never noticed. Satisfying the path it asks for keeps the
sources byte-identical to the tag.

## Why Electron 33 is not pinned

Upstream pins Electron 33 because of the crash in
`docs/MESA-DRI-CRASH-FIX.md`, but **that root cause is snap-specific**: the snap
mounts the `gnome-3-28-1804` content snap, whose DRI drivers are from 2018, and
Electron 40+'s ANGLE segfaults in Mesa's loader when it probes them.

Nothing here goes through a snap runtime. `electron` from nixpkgs uses the host's
Mesa / driver stack via `hardware.graphics`, so there is no 2018-era DRI driver to
trip over, and nixpkgs no longer carries `electron_33` in any case (EOL, removed).

The package therefore takes nixpkgs' default `electron` (41.x at the time of
writing). It is a plain function argument, so swapping it is easy if a specific
version ever misbehaves:

```nix
pkgs.chatgpt-desktop-linux.override { electron = pkgs.electron_39; }
```

The Electron actually used is also readable at `passthru.electron`.

## Usage

```nix
{
  inputs.chatgpt.url = "github:solitarywalker/chatgpt.nix";
}
```

As a package:

```nix
inputs.chatgpt.packages.${pkgs.stdenv.hostPlatform.system}.default
```

As an overlay:

```nix
nixpkgs.overlays = [ inputs.chatgpt.overlays.default ];
# => pkgs.chatgpt-desktop-linux
```

No NixOS module is provided, because none is needed — there is no writable state
directory to prepare and no session variable to set. Adding the package to
`environment.systemPackages` is enough.

## Wayland

`--ozone-platform-hint=auto` and `--enable-features=WaylandWindowDecorations` are
added by the wrapper, but only when `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are both
set, so an X11 session is left alone. Without the decorations flag a
Wayland-native Electron window comes up with no title bar.

## Development

```sh
nix build          # result/bin/chatgpt-desktop-linux
nix fmt            # nixfmt-tree
```

Updating to a new upstream tag means refreshing two hashes — `src.hash` and
`npmDepsHash`. The latter comes from:

```sh
nix shell nixpkgs#prefetch-npm-deps --command prefetch-npm-deps package-lock.json
```

## Supported platforms

`meta.platforms` is `linux`, and this has only been exercised on x86_64-linux.

**What has actually been verified:** the derivation builds, the output tree is
correct, and the app initialises and stays running under Xvfb with software
rendering — so the ESM entry point and its dependencies do load under Electron 41.
Loading `chatgpt.com` and the `StartupWMClass` match were **not** verifiable in a
sandbox without network or a real compositor, so treat those as untested.

`StartupWMClass=ChatGPT` follows from `app.setName('ChatGPT')` in `main.js`, which
is what Electron derives WM_CLASS from. If a launcher entry does not light up when
the window opens, check the real WM_CLASS with `xprop WM_CLASS` and adjust.

## A note on trust

This upstream is a small project (single author, a handful of stars). Its entire
source is three short files, and they are worth reading before installing: the app
loads `chatgpt.com` with `contextIsolation: true` and `nodeIntegration: false`, has
an empty preload script that exposes nothing over the context bridge, spoofs a
Chrome user agent, and sends Google sign-in to the external browser. No telemetry
and no remote code loading — but it is your logged-in session, so verify that for
yourself rather than taking this paragraph's word for it.

## On AI generation

The Nix expressions (`chatgpt.nix`, `flake.nix`) and this README were written with
the help of [Claude Code](https://claude.com/claude-code) and then reviewed and
corrected by hand. The relevant commits carry a
`Co-Authored-By: Claude <noreply@anthropic.com>` trailer.

The upstream sources that get installed are untouched, apart from the two
`package.json` version specs described above.

## License

The Nix expressions in this repository are [MIT](./LICENSE). chatgpt-desktop-linux
itself is not included here — it is fetched at build time — and is under its own
license (its `LICENSE` says MIT; note that its `package.json` says `ISC`).
