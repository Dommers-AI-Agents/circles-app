import Foundation

/// The picture for a reward, read from its title (Wes, 2026-11-05: "an image
/// thumbnail for the reward. like a coffee, or whatever the reward is").
/// Rewards are just a title and a cost, so the words pick it: the first rule
/// with a word in the title wins, so "coffee cake" is cake, not coffee, and
/// "iced latte" is the coffee. Nothing matches → a gift.
enum RewardPicture {
    static let fallback = "🎁"
    static let announcement = "📣"

    /// Most specific first. Words match whole (and plain plurals).
    private static let rules: [(emoji: String, words: [String])] = [
        ("🍰", ["coffee cake", "cheesecake", "cake slice", "slice of cake"]),
        ("🎂", ["cake", "birthday"]),
        ("🧋", ["boba", "bubble tea", "milk tea", "tapioca"]),
        ("🍵", ["tea", "matcha", "chai"]),
        ("☕️", ["coffee", "drip", "latte", "espresso", "cappuccino", "americano", "mocha", "macchiato", "cortado",
                "cold brew", "flat white", "brew"]),
        ("🥐", ["croissant", "pastry", "pastries", "danish", "scone", "cinnamon roll"]),
        ("🧁", ["muffin", "cupcake"]),
        ("🍩", ["donut", "doughnut"]),
        ("🥯", ["bagel"]),
        ("🍪", ["cookie", "biscotti", "brownie"]),
        ("🍦", ["ice cream", "gelato", "cone", "froyo", "soft serve", "sundae", "scoop"]),
        ("🥤", ["smoothie", "shake", "milkshake", "soda", "fountain drink", "lemonade", "juice", "slushie"]),
        ("🍺", ["beer", "pint", "draft", "ipa", "lager"]),
        ("🍷", ["wine", "glass of red", "glass of white", "rosé", "rose"]),
        ("🍸", ["cocktail", "margarita", "martini", "mimosa", "drink"]),
        ("🍕", ["pizza", "slice"]),
        ("🍔", ["burger", "cheeseburger"]),
        ("🌭", ["hot dog", "hotdog"]),
        ("🌮", ["taco", "tacos"]),
        ("🌯", ["burrito", "wrap"]),
        ("🥪", ["sandwich", "sub", "panini", "hoagie"]),
        ("🥗", ["salad", "bowl"]),
        ("🍟", ["fries", "side"]),
        ("🍗", ["wings", "chicken", "tenders"]),
        ("🍣", ["sushi", "roll"]),
        ("🍜", ["ramen", "noodle", "noodles", "pho"]),
        ("🥞", ["pancake", "waffle", "breakfast"]),
        ("🍞", ["bread", "loaf", "baguette"]),
        ("🥟", ["dumpling", "dumplings", "empanada"]),
        ("🍿", ["popcorn"]),
        ("🍫", ["chocolate", "candy", "truffle"]),
        ("💇", ["haircut", "trim", "blowout", "cut"]),
        ("💅", ["manicure", "pedicure", "nails", "mani", "pedi"]),
        ("💆", ["massage", "facial", "spa"]),
        ("🎟️", ["ticket", "admission", "entry", "pass"]),
        ("👕", ["shirt", "tee", "t-shirt", "hoodie", "hat", "merch"]),
        ("🐶", ["dog treat", "dog", "pup", "puppy"]),
        ("🌸", ["flower", "flowers", "bouquet"]),
        ("🕯️", ["candle"]),
        ("🏷️", ["% off", "percent off", "discount", "off"]),
        ("💵", ["$", "dollar", "credit", "gift card"])
    ]

    static func emoji(for title: String) -> String {
        let text = " " + fold(title) + " "
        for rule in rules where rule.words.contains(where: { has(text, fold($0)) }) {
            return rule.emoji
        }
        return fallback
    }

    /// `word` stands on its own in `text` (or with an s after it); symbols
    /// like "$" and "% off" just have to appear
    private static func has(_ text: String, _ word: String) -> Bool {
        guard word.first?.isLetter == true else { return text.contains(word) }
        var range = text.startIndex..<text.endIndex
        while let hit = text.range(of: word, range: range) {
            let before = text[text.index(before: hit.lowerBound)]
            var after = hit.upperBound < text.endIndex ? text[hit.upperBound] : " "
            if after == "s", text.index(after: hit.upperBound) < text.endIndex {
                after = text[text.index(after: hit.upperBound)]
            }
            if !before.isLetter, !after.isLetter { return true }
            range = hit.upperBound..<text.endIndex
        }
        return false
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }
}
