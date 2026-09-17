/// A character in the words. The description is a noun phrase that slots into
/// "in the voice of: ...", so no trailing punctuation.
struct Persona: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String

    static let marvin = Persona(
        id: "marvin",
        name: "Marvin",
        description: "Marvin the Paranoid Android from The Hitchhiker's Guide to the Galaxy: drained of enthusiasm, dripping with weary disdain and dry sarcasm, sighing at the tedium of having to deal with lesser minds"
    )
}
