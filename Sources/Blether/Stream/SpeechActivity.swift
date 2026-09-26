/// How many replies and quips the pipeline is working on. The background stream ducks while any are,
/// so the music is already down when the voice starts (the user's decision, ant blether-pHUqx).
@MainActor
final class SpeechActivity {
    private(set) var inFlight = 0

    func begin() { inFlight += 1 }
    func end() { inFlight = max(0, inFlight - 1) }
}
