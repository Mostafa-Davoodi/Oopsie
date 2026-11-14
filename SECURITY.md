# Security policy

## Report a problem privately

Please don't open a public issue for a security problem.

Report it with GitHub's private vulnerability reporting: [open a private report](https://github.com/Mostafa-Davoodi/Oopsie/security/advisories/new). Only the maintainer can see it.

Please include:

- What the problem is, and what someone could do with it.
- Steps to reproduce it.
- Your Oopsie version, macOS version, and `container --version`.

I aim to reply within a week. Once a fix is released, the advisory is published and you're credited, unless you'd rather not be.

## Supported versions

Only the latest release gets security fixes.

## In scope

Problems in Oopsie's own code or releases, for example:

- A machine can read or change files on the Mac outside the folder you chose to share.
- A machine can be reached from computers other than your Mac.
- Oopsie's SSH key (`~/.ssh/oopsie_ed25519`) is created with unsafe permissions, or is exposed.
- A folder name, machine name or other input can make Oopsie run a command you didn't ask for.
- A problem with how releases or the Homebrew cask are built or published.

## Out of scope

- Problems in Apple's `container` tool or in macOS virtualization. Report those to Apple, in the [apple/container](https://github.com/apple/container) project.
- What you run inside your own machines. Machines are meant to be broken.
- Documented design choices:
  - Shared folders can be written to from the machine. That's what sharing is for.
  - Oopsie's SSH command turns off host key checking, because machines are thrown away and IP addresses are reused.
