import Foundation

/// A cuisine/flavor proposal. Manual entries get the fallback fork-and-knife emoji.
struct Cuisine: Equatable, Hashable {
    let name: String
    let emoji: String
}

/// The built-in pool — the one editable place to tweak what the dice can roll.
enum CuisinePool {
    static let all: [Cuisine] = [
        Cuisine(name: "Hotpot", emoji: "🍲"),
        Cuisine(name: "Sichuan", emoji: "🌶️"),
        Cuisine(name: "Cantonese", emoji: "🦆"),
        Cuisine(name: "Dim Sum", emoji: "🥟"),
        Cuisine(name: "Dumplings", emoji: "🥟"),
        Cuisine(name: "Malatang", emoji: "🍢"),
        Cuisine(name: "Hand-pulled Noodles", emoji: "🍜"),
        Cuisine(name: "Congee", emoji: "🥣"),
        Cuisine(name: "Taiwanese", emoji: "🍱"),
        Cuisine(name: "Ramen", emoji: "🍜"),
        Cuisine(name: "Sushi", emoji: "🍣"),
        Cuisine(name: "Udon", emoji: "🍜"),
        Cuisine(name: "Tonkatsu", emoji: "🍱"),
        Cuisine(name: "Japanese Curry", emoji: "🍛"),
        Cuisine(name: "Izakaya", emoji: "🍶"),
        Cuisine(name: "Korean BBQ", emoji: "🥩"),
        Cuisine(name: "Bibimbap", emoji: "🍚"),
        Cuisine(name: "Korean Fried Chicken", emoji: "🍗"),
        Cuisine(name: "Pho", emoji: "🍜"),
        Cuisine(name: "Banh Mi", emoji: "🥖"),
        Cuisine(name: "Thai", emoji: "🍛"),
        Cuisine(name: "Indian", emoji: "🍛"),
        Cuisine(name: "Pizza", emoji: "🍕"),
        Cuisine(name: "Pasta", emoji: "🍝"),
        Cuisine(name: "Burgers", emoji: "🍔"),
        Cuisine(name: "Sandwiches", emoji: "🥪"),
        Cuisine(name: "Fried Chicken", emoji: "🍗"),
        Cuisine(name: "American BBQ", emoji: "🍖"),
        Cuisine(name: "Steakhouse", emoji: "🥩"),
        Cuisine(name: "Seafood", emoji: "🦞"),
        Cuisine(name: "Lobster Roll", emoji: "🦞"),
        Cuisine(name: "Tacos", emoji: "🌮"),
        Cuisine(name: "Burritos", emoji: "🌯"),
        Cuisine(name: "Shawarma", emoji: "🌯"),
        Cuisine(name: "Falafel", emoji: "🧆"),
        Cuisine(name: "Mediterranean", emoji: "🥙"),
        Cuisine(name: "Greek", emoji: "🥗"),
        Cuisine(name: "Poke", emoji: "🥗"),
        Cuisine(name: "Brunch", emoji: "🥞"),
    ]

    /// Purely random draw (open question resolved for v1: no history bias yet).
    /// Excluding the current proposal keeps a re-roll from repeating itself.
    static func draw(excluding excluded: Cuisine? = nil) -> Cuisine {
        let candidates = all.filter { $0 != excluded }
        return candidates.randomElement() ?? all[0]
    }
}
