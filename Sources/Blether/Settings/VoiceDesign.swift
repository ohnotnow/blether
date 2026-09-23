/// A Breeze voice: a name and a written description of how it sounds. Not a persona, which says
/// what to say (blether-WtzbG). The four defaults were heard and approved by the user on 2026-09-22
/// (blether-gzXn6, blether-uHwCr); detailed descriptions like these keep the voice the same actor
/// from clip to clip, where a one-line character sketch does not. Quality is per design, so a short
/// preamble can be Better while a long reply is Faster (blether-vNbF9); duplicate a design for both.
struct VoiceDesign: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var description: String
    var quality: BreezeQuality = .better

    /// First, because the first design is the fallback for a deleted one and she speaks at a normal pace.
    static let servalan = VoiceDesign(
        id: "servalan",
        name: "Servalan",
        description: "Studio-quality recording. English Female, mid-thirties, cultured aristocratic Received Pronunciation. Deep, dark, sultry contralto, low in the chest, with a velvety, purring, smoky huskiness. Strong, fast, instructive but seductive delivery, every consonant precise. Cool, silky, faintly amused menace. A glamorous villain entirely in control."
    )
    static let marvin = VoiceDesign(
        id: "marvin",
        name: "Marvin",
        description: "Male, middle-aged, refined southern English accent. Low, soft baritone with a faintly metallic, hollow texture. Slow, weary, deflated delivery with long sighing pauses. Monotone, resigned, quietly sardonic. Utterly unimpressed."
    )
    static let danishDetective = VoiceDesign(
        id: "danish-detective",
        name: "Danish Detective",
        description: "Female, young adult, late twenties, Danish-accented English with a soft Scandinavian lilt. Police detective in a bleak Nordic crime drama. Slightly dusky, low alto with a soft, faintly husky texture. Hesitant, thoughtful delivery with small pauses, a gentle sing-song rise and fall. Earnest, serious, quietly melancholy, intelligent."
    )
    static let theGuide = VoiceDesign(
        id: "the-guide",
        name: "The Guide",
        description: "Male, late fifties, well-spoken educated English accent. Narrator of a nineteen-seventies radio documentary. Warm, dry, slightly nasal baritone with a gentle, avuncular texture. Brisk, factual, matter-of-fact delivery, steady pace, no dramatic pauses. Mildly weary and faintly disappointed, as if the universe has let him down yet again."
    )

    static let defaults = [servalan, marvin, danishDetective, theGuide]

    /// How a design appears in a voice picker. Grouped under English, the language of the replies.
    var voice: Voice { Voice(id: id, name: name, language: "en") }
}

extension VoiceDesign {
    /// Designs stored before quality was per design have none; they read as Better.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        quality = try container.decodeIfPresent(BreezeQuality.self, forKey: .quality) ?? .better
    }
}

/// A design's quality: Breeze's classifier-free guidance scale. Better is noticeably richer and
/// takes about twice as long.
enum BreezeQuality: String, Codable, CaseIterable, Sendable {
    case faster, better

    var cfgScale: Double {
        switch self {
        case .faster: 1
        case .better: 4
        }
    }

    var displayName: String {
        switch self {
        case .faster: "Faster"
        case .better: "Better"
        }
    }
}
