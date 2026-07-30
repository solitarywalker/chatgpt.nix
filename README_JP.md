# chatgpt.nix

[English](./README.md) | 日本語

[evildevill/chatgpt-desktop-linux](https://github.com/evildevill/chatgpt-desktop-linux)
— <https://chatgpt.com> を表示する Electron アプリ — を NixOS 向けに Nix でパッケージ
する flake。

上流は snap を配布している。この flake は `v1.0.2` タグから同じソースをビルドし、
代わりにラッパー・`.desktop` エントリ・アイコンを提供する。

## lencx/ChatGPT を使わない理由

[lencx/ChatGPT](https://github.com/lencx/chatgpt) の方が有名なデスクトップ
クライアントで、このリポジトリも元々そちらをパッケージする予定だった。
だが現行の nixpkgs ではビルドできない。

あれは **Tauri 1.3** のアプリ (`wry 0.24.3`, `webkit2gtk-sys 0.18`, `soup2-sys`)
なので webkit2gtk-4.0 / libsoup 2.4 のスタックを要求する。それが nixpkgs から
すべて削除されている:

| 属性 | 状態 |
|---|---|
| `webkitgtk_4_0` | 削除 — *"port to `libsoup_3` and switch to `webkitgtk_4_1`"* |
| `libsoup_2_4` | 削除 — *"end-of-life and has many known unfixed security issues"* |
| `cargo-tauri_1` | 削除 — *"required webkitgtk 4.0 and libsoup 2.4"* |

webkit2gtk-4.1 対応は Tauri 2.x から入ったもので 1.x 系には来ていないため、
パッチで前に進む道はない。nixpkgs 25.05 (まだ 3 つとも残っている) を pin すれば
ビルドは通るが、それはログイン済みの ChatGPT セッションを描画させるために EOL の
WebKit を抱え続けることを意味する。加えて上流は 2024 年 8 月からアーカイブ済みで、
いまはリダイレクトにしかならない `https://chat.openai.com` をハードコードしたまま。

こちらの上流は Electron なので以上はどれも当てはまらない。webkitgtk も libsoup も
不要で、最初から `chatgpt.com` を指している。

## このパッケージがやること

コンパイル工程は無い。`src/main.js`・`src/preload.js`・`src/config/index.js` は
Electron がそのまま実行する素の ESM で、上流の `npm run dist:*` はそれを
snap / AppImage / deb に包むだけ — つまりこの derivation が置き換える対象そのもの。
よってビルドは、依存の閉包を取得し、ソースを store に置き、`electron` にそこを
指させるだけ。

インストールされるのは実行時の 19 パッケージのみ。`--omit=dev` で electron・
electron-builder・eslint・prettier を落としている。このアプリに走らせるバンドラは
無く、ビルド時に lint する必要も無く、Electron 自体は nixpkgs から来るため。

## 上流の不備と、その扱い

| 問題 | 対処 |
|---|---|
| `package.json` と `package-lock.json` の electron のバージョンが食い違い、`npm ci` が動作を拒否する | `package.json` を lockfile に合わせてパッチ |
| `main.js` がウィンドウアイコンを `src/assets/icon.png` に探すが、実体は `assets/icon.png` にある | 要求されたパスに symlink を置く |
| `electron-context-menu` がリリース版の右クリックメニューに "Inspect Element" を出す | `ELECTRON_IS_DEV=0` を既定で設定 |

### lockfile の不整合

`docs/MESA-DRI-CRASH-FIX.md` には Electron 40 → 33 へのダウングレードが書かれて
おり、`package.json` も確かに `^33.2.0` / `^25.1.8` へ変更されている。
**しかし lockfile は再生成されていない** ため、いまも electron 40.2.1 /
electron-builder 26.7.0 に解決される。npm は lockfile が満たせない範囲指定を見て
`electron` をレジストリに再解決しようとし、Nix のビルドはオフラインなので
`ENOTCACHED` で失敗する。

逆方向ではなく `package.json` を lockfile に合わせている。`npmDepsHash` は lockfile
に対して取られ、`npmConfigHook` がキャッシュ側の複製と diff するので、lockfile を
編集しても `npmDepsHash is out of date` に置き換わるだけだから。どちらのパッケージも
`--omit=dev` で落ちるので、ここに書いたバージョンが実際に入ることはない —
範囲チェックだけが読む。

パッチには `--replace-fail` を使っている。上流が lockfile を再生成したら、
黙って誤ったパッチを当てるのではなく、はっきり失敗するように。

### アイコンのパス

`main.js` は
`path.join(path.dirname(fileURLToPath(import.meta.url)), 'assets/icon.png')`
としてパスを組むが、`import.meta.url` は `.../src/main.js` なので
`src/assets/icon.png` に解決される。実体はリポジトリ直下。Electron は存在しない
アイコンパスを黙って無視するので、上流はこれに気づいていない。要求される側のパスを
用意すれば、ソースをタグのまま (バイト単位で同一に) 保てる。

## Electron 33 を pin しない理由

上流が Electron 33 を pin しているのは `docs/MESA-DRI-CRASH-FIX.md` のクラッシュ
のためだが、**その原因は snap 固有**。snap は `gnome-3-28-1804` content snap を
マウントし、そこの DRI ドライバは 2018 年製で、Electron 40+ の ANGLE がそれを
プローブすると Mesa のローダ内で segfault する。

ここでは snap のランタイムを一切通らない。nixpkgs の `electron` は
`hardware.graphics` 経由でホストの Mesa / ドライバスタックを使うので、つまずく
2018 年製 DRI ドライバは存在しない。そもそも nixpkgs には `electron_33` は
もう無い (EOL のため削除)。

したがって nixpkgs 既定の `electron` (執筆時点で 41.x) を使う。ただの関数引数なので、
特定バージョンで問題が出たら差し替えは容易:

```nix
pkgs.chatgpt-desktop-linux.override { electron = pkgs.electron_39; }
```

実際に使われている Electron は `passthru.electron` から読める。

## 使い方

```nix
{
  inputs.chatgpt.url = "github:solitarywalker/chatgpt.nix";
}
```

パッケージとして:

```nix
inputs.chatgpt.packages.${pkgs.stdenv.hostPlatform.system}.default
```

overlay として:

```nix
nixpkgs.overlays = [ inputs.chatgpt.overlays.default ];
# => pkgs.chatgpt-desktop-linux
```

NixOS モジュールは提供しない。必要が無いため — 用意すべき書き込み可能な状態
ディレクトリも、設定すべきセッション変数も無い。`environment.systemPackages` に
パッケージを追加すれば足りる。

## Wayland

ラッパーが `--ozone-platform-hint=auto` と
`--enable-features=WaylandWindowDecorations` を付けるが、`NIXOS_OZONE_WL` と
`WAYLAND_DISPLAY` の両方が設定されている場合のみなので、X11 セッションには
手を出さない。装飾のフラグが無いと Wayland ネイティブの Electron ウィンドウは
タイトルバー無しで出てくる。

## 開発

```sh
nix build          # result/bin/chatgpt-desktop-linux
nix fmt            # nixfmt-tree
```

上流の新しいタグへ更新するときは、`src.hash` と `npmDepsHash` の 2 つを更新する。
後者はこれで得られる:

```sh
nix shell nixpkgs#prefetch-npm-deps --command prefetch-npm-deps package-lock.json
```

## 対応プラットフォーム

`meta.platforms` は `linux`。動作確認したのは x86_64-linux のみ。

**実際に確認できたこと:** derivation がビルドできること、出力ツリーが正しいこと、
そして Xvfb + ソフトウェアレンダリングでアプリが初期化され動き続けること —
つまり ESM のエントリポイントとその依存が Electron 41 で読み込めること。
`chatgpt.com` の読み込みと `StartupWMClass` の一致は、ネットワークも実際の
コンポジタも無いサンドボックスでは**確認できなかった**ので、未検証として扱うこと。

`StartupWMClass=ChatGPT` は `main.js` の `app.setName('ChatGPT')` に由来する
(Electron が WM_CLASS をそこから導出する)。ウィンドウを開いてもランチャー
エントリが反応しない場合は `xprop WM_CLASS` で実際の値を見て調整する。

## 信頼について

この上流は小さなプロジェクト (作者 1 人、star も僅か)。ソース全体が短い 3
ファイルなので、入れる前に読む価値がある: アプリは `contextIsolation: true` /
`nodeIntegration: false` で `chatgpt.com` を読み込み、preload は空でコンテキスト
ブリッジに何も公開せず、Chrome の user agent を偽装し、Google サインインは外部
ブラウザに投げる。テレメトリもリモートコードの読み込みも無い — とはいえ自分の
ログイン済みセッションを預けるのだから、この段落を信じるのではなく自分で確認する
のがよい。

## 生成について

このリポジトリの Nix 式 (`chatgpt.nix`, `flake.nix`) と本 README は、
[Claude Code](https://claude.com/claude-code) による自動生成を利用して書かれ、
人手でレビュー・修正したもの。該当するコミットには
`Co-Authored-By: Claude <noreply@anthropic.com>` が付いている。

インストールされる上流のソースには、上記の `package.json` の 2 つのバージョン指定を
除いて手を入れていない。

## ライセンス

このリポジトリの Nix 式は [MIT](./LICENSE)。chatgpt-desktop-linux 本体はここには
含まれず、ビルド時に取得され、それ自身のライセンスに従う (`LICENSE` は MIT。
なお `package.json` には `ISC` と書かれている)。
