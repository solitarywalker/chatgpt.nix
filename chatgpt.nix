# evildevill/chatgpt-desktop-linux — an Electron shell around https://chatgpt.com.
#
# There is no compile step here. main.js / preload.js / config/index.js are plain
# ESM that Electron runs as-is; upstream's own `npm run dist:*` targets only wrap
# them into a snap / AppImage / deb, which is exactly the packaging this
# derivation replaces. So the build is: fetch the dependency closure, drop the
# sources into the store, and point an electron at them.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  electron,
}:

buildNpmPackage (finalAttrs: {
  pname = "chatgpt-desktop-linux";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "evildevill";
    repo = "chatgpt-desktop-linux";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XotEoNdYcNyGLnUg3Mxmkh8/FJ7kTS1bEqQvzovyBYs=";
  };

  npmDepsHash = "sha256-x/3JCmgrBXtPgElnYox1cQ+J7msXFk0lnEWxGkrcrP8=";

  # The lockfile's devDependencies are electron, electron-builder, eslint and
  # prettier — a bundler this app does not have, and linters. None of them are
  # needed to run it, and skipping electron in particular avoids its postinstall,
  # which would otherwise try to download a prebuilt binary over the network.
  #
  # npmDepsHash still covers the whole lockfile (fetchNpmDeps hashes it in full,
  # with no notion of --omit). The cache simply ends up holding more than `npm ci`
  # installs from it, which is harmless.
  npmFlags = [ "--omit=dev" ];

  # Upstream's package.json and package-lock.json disagree, and `npm ci` refuses to
  # run when they do.
  #
  # docs/MESA-DRI-CRASH-FIX.md describes downgrading electron 40 -> 33 to dodge a
  # segfault, and package.json was duly changed to ^33.2.0 / ^25.1.8 — but the
  # lockfile never got regenerated and still resolves electron 40.2.1 /
  # electron-builder 26.7.0. npm notices the ranges are unsatisfiable, tries to
  # re-resolve electron against the registry, and fails as ENOTCACHED because the
  # build is offline.
  #
  # Align package.json with the lockfile rather than the reverse: the lockfile is
  # what npmDepsHash is taken over, and npmConfigHook diffs it against the cache's
  # copy, so editing it here would just trade this error for "npmDepsHash is out of
  # date". Both packages are devDependencies dropped by --omit=dev, so the versions
  # named here are never actually installed — only the range check reads them.
  #
  # --replace-fail, so that if upstream ever regenerates the lockfile this build
  # breaks loudly instead of quietly patching the wrong thing.
  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"electron": "^33.2.0"' '"electron": "^40.2.1"' \
      --replace-fail '"electron-builder": "^25.1.8"' '"electron-builder": "^26.7.0"'
  '';

  # package.json has no "build" script — only "dist*" targets for electron-builder.
  dontNpmBuild = true;

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/chatgpt-desktop-linux
    cp -r src assets node_modules package.json $out/share/chatgpt-desktop-linux/

    # Upstream bug, not a packaging workaround. main.js builds its BrowserWindow
    # icon as
    #   path.join(path.dirname(fileURLToPath(import.meta.url)), 'assets/icon.png')
    # and import.meta.url is .../src/main.js, so it resolves to src/assets/icon.png
    # while the file actually ships at assets/icon.png in the repo root. Electron
    # silently ignores a missing icon path, so upstream never noticed. Satisfy the
    # path it asks for rather than patching main.js, which keeps the source
    # byte-identical to the tag.
    mkdir -p $out/share/chatgpt-desktop-linux/src/assets
    ln -s ../../assets/icon.png $out/share/chatgpt-desktop-linux/src/assets/icon.png

    # 500x500 is the icon's real size, so that is the theme directory it belongs
    # in — declaring it as 512x512 would make the DE scale it wrongly. hicolor at
    # a non-standard size is looked up fine, but share/pixmaps is what the older
    # lookup path reads, so install to both.
    install -Dm644 assets/icon.png \
      $out/share/icons/hicolor/500x500/apps/chatgpt-desktop-linux.png
    install -Dm644 assets/icon.png $out/share/pixmaps/chatgpt-desktop-linux.png

    # --ozone-platform-hint=auto is gated on NIXOS_OZONE_WL so that an X11 session
    # is left alone. WaylandWindowDecorations gets the window its own decorations;
    # without it a Wayland-native Electron window comes up undecorated.
    #
    # ELECTRON_IS_DEV=0 is not cosmetic. electron-context-menu decides its
    # showInspectElement default from electron-is-dev, which falls back to
    # !app.isPackaged — and running `electron <dir>` is by definition not packaged,
    # so an unset variable would put "Inspect Element" in the right-click menu of
    # what is supposed to be a finished app. --set-default leaves it overridable.
    makeWrapper ${lib.getExe electron} $out/bin/chatgpt-desktop-linux \
      --add-flags $out/share/chatgpt-desktop-linux \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}" \
      --set-default ELECTRON_IS_DEV 0 \
      --inherit-argv0

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "chatgpt-desktop-linux";
      desktopName = "ChatGPT";
      genericName = "AI Chat Client";
      comment = "Unofficial ChatGPT desktop client";
      exec = "chatgpt-desktop-linux %U";
      icon = "chatgpt-desktop-linux";
      terminal = false;
      categories = [
        "Network"
        "Utility"
      ];
      # main.js registers a second-instance handler that accepts chatgpt:// and
      # forwards the rest of the URI to chatgpt.com, hence %U above and this
      # scheme. Note that it never calls app.setAsDefaultProtocolClient, so the
      # association only exists because this entry declares it.
      mimeTypes = [ "x-scheme-handler/chatgpt" ];
      # main.js calls app.setName('ChatGPT'), which is what Electron derives
      # WM_CLASS from. Needed for the window to match the launcher entry when
      # pinned to a panel.
      startupWMClass = "ChatGPT";
    })
  ];

  passthru = {
    inherit electron;
  };

  meta = {
    description = "Unofficial ChatGPT desktop client (Electron) for NixOS";
    longDescription = ''
      Packages evildevill/chatgpt-desktop-linux, an Electron window onto
      https://chatgpt.com, together with the wrapper and .desktop entry it needs
      on NixOS. Upstream ships a snap; this builds the same sources from the
      v${finalAttrs.version} tag instead.
    '';
    homepage = "https://github.com/evildevill/chatgpt-desktop-linux";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "chatgpt-desktop-linux";
  };
})
