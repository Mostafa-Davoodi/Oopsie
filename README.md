# 💥 Oopsie

**Break Linux. Not your Mac.**

Oopsie is a tiny menu bar app that gives you a disposable Linux machine in one click. Spawn it, mess it up, blow it away, and start fresh.

```
Spawn → Play → Break → Repeat
```

- **🐧 Spawn Linux** starts a fresh Ubuntu machine and drops you into a full interactive terminal, right in the menu bar.
- **💥 Oopsie!** destroys the machine and everything in it, with a small explosion. *"Well, that happened."*
- **🔄 Do It Again** gives you a brand-new machine.
- **🪦 Body count** tracks how many Linuxes you've destroyed. Your rank goes from *Pristine* up to *rm -rf Royalty*.

No settings, no dashboards, no container management. That's on purpose.

## Requirements

- A Mac with Apple silicon
- macOS 26 (Tahoe) is recommended. Apple's `container` also runs on macOS 15, but with networking limits.
- Apple's [`container`](https://github.com/apple/container/releases) CLI. Install the signed `.pkg` from the releases page.
- Xcode 26 (or its command line tools). The SwiftTerm dependency needs Swift 6.2.

You don't need to start the container engine yourself. Oopsie starts it on first spawn and installs the default kernel if it's missing.

## Build & run

```bash
./make-app.sh             # builds build/Oopsie.app
./make-app.sh --install   # builds, copies to /Applications, launches
```

To hack on it, run `swift run` from the repo, or `open Package.swift` in Xcode and press Run.

The first spawn downloads the Ubuntu image (about 30 MB) once. After that, a new machine takes a couple of seconds.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘↩ | Spawn Linux / Do It Again |
| ⌘⌫ | Oopsie! (destroy) |
| ⌘C / ⌘V / ⌘A | Copy / paste / select all in the terminal |

Easter eggs: click the penguin, and the red dot on the terminal's title bar also works as an Oopsie button.

## How it works

Oopsie is a small wrapper around Apple's `container` CLI:

| Action | Under the hood |
| --- | --- |
| Spawn | `container run --detach --name oopsie-xxxx ubuntu:latest sleep infinity` |
| Terminal | `container exec --interactive --tty oopsie-xxxx bash`, hosted in [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) |
| Oopsie! | `container delete --force oopsie-xxxx` |

Each machine is a lightweight VM, so even `rm -rf --no-preserve-root /` only breaks the penguin. If you type `exit`, the machine keeps running and you can jump back in. Quitting Oopsie destroys the current machine. Leftover `oopsie-*` machines from a crash are cleaned up the next time Oopsie launches.

## Project layout

```
Sources/Oopsie/
  OopsieApp.swift       menu bar scene, app delegate, status icon
  OopsieStore.swift     the Spawn → Play → Break → Repeat state machine
  ContainerCLI.swift    talks to Apple's `container`
  TerminalSession.swift SwiftTerm terminal and its "Grape Soda" theme
  PopoverView.swift     every screen in the popover
  Effects.swift         chunky buttons, shake effect, explosion
  Quips.swift           all the jokes
```

Want a different distro? Change `ContainerCLI.image`, for example to `docker.io/library/alpine:latest`. Alpine has no `bash`, so also change the shell in `shellArguments` to `sh`.
