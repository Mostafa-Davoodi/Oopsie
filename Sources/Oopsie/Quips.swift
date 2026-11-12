import Foundation

/// All of Oopsie's personality lives here.
enum Quips {
    static let idle = [
        "Nothing to break. Yet.",
        "Your Mac is safe. For now.",
        "A blank slate. Suspiciously clean.",
        "No penguins were harmed. Yet.",
    ]

    static let spawning = [
        "Summoning a penguin…",
        "Unboxing Linux…",
        "Bribing the kernel…",
        "Inflating a tiny datacenter…",
        "Assembling root privileges…",
    ]

    /// Subtitles under the mandatory "Well, that happened."
    static let destroyed = [
        "Oopsie! It's gone.",
        "It's like it never existed.",
        "Every byte, gone. Very zen.",
        "The penguin has left the building.",
        "No logs. No witnesses.",
        "Back to the void it goes.",
    ]

    static let tips = [
        "Go on, `rm -rf --no-preserve-root /`. We dare you.",
        "`apt update && apt install -y cowsay` — trust us.",
        "`chmod -R 000 /` is a classic.",
        "Nothing in here can touch your Mac.",
        "`:(){ :|:& };:` — the forbidden emoticon.",
        "`apt install -y sl` and then mistype `ls`.",
        "`mv /bin /nope` and see what happens.",
        "`echo 'oops' > /etc/passwd` is a choice.",
    ]

    static func rank(for count: Int) -> String {
        switch count {
        case 0: return "Pristine"
        case 1..<5: return "First Oopsie"
        case 5..<15: return "Apprentice Breaker"
        case 15..<42: return "Chaos Intern"
        case 42..<100: return "Penguin Botherer"
        case 100..<250: return "Agent of Entropy"
        default: return "rm -rf Royalty"
        }
    }
}
