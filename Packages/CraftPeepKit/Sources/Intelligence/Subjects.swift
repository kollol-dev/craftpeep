import Domain

/// The subject areas the app has dedicated views for.
public enum Subjects {
    /// Stories about AI: tagged with an AI topic or lab, or published by a source whose main subject is AI.
    public static let ai = StoryFilter.Subject(
        entityNames: [
            "AI", "AI agents", "OpenAI", "Anthropic", "Google DeepMind", "Mistral", "xAI", "Hugging Face", "NVIDIA"
        ],
        sourceTopic: "ai"
    )
}
