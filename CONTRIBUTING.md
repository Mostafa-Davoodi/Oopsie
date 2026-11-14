# Contributing to Oopsie

Thanks for helping. Oopsie is a small, native macOS menu bar app, and the goal is to keep it that way: few features, done well, in plain words.

## Before you start

- **Small fixes** (typos, clear bugs, docs): open a pull request.
- **New features or bigger changes**: open an issue first, so we can agree on the idea before you write the code.
- **Security problems**: don't open an issue. Follow [SECURITY.md](SECURITY.md).

## Set up

You need an Apple silicon Mac, macOS 15 or later, and Xcode 16 or later.

```bash
git clone https://github.com/Mostafa-Davoodi/Oopsie.git
cd Oopsie
swift build
swift test
```

Run the app from source:

```bash
swift run
```

You don't need real machines to work on the menu. The fake `container` script shows one running and one stopped machine:

```bash
OOPSIE_CONTAINER="$PWD/scripts/fake-container" swift run
```

To build the full app bundle (needed for notifications), run `./make-app.sh`.

## Making a change

- Keep each pull request to one change.
- Add or update tests in `Tests/OopsieTests` for logic you change, especially parsing and anything that builds shell commands.
- Update the README when you change what the user sees or does.
- Use plain, short words in the menu, error messages and docs.
- Don't add a package dependency without talking about it in an issue first. Oopsie has none today.
- CI must pass: it builds the app and runs `swift test` on macOS.

## Sign your commits (DCO)

Oopsie uses the [Developer Certificate of Origin](https://developercertificate.org) (DCO) instead of a contributor license agreement. By signing off a commit, you confirm that you wrote the change, or have the right to submit it, under the project's license.

Add the sign-off with `-s`:

```bash
git commit -s -m "Fix the IP address shown for stopped machines"
```

This adds a line like this to the commit message:

```
Signed-off-by: Your Name <you@example.com>
```

Forgot? Fix the last commit with `git commit --amend -s --no-edit`, or every commit on your branch with `git rebase --signoff main`, then force-push your branch.

## License

Oopsie is licensed under the [Apache License 2.0](LICENSE). Your contributions are licensed under the same license.
