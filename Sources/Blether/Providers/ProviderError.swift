enum ProviderError: Error, Equatable {
    case unknownVoice(String)
    case noAudio
    case timedOut
    case http(Int)
    case other(String)
}
