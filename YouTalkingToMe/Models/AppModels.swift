import AppKit
import Foundation

enum ModelTier: String, CaseIterable, Identifiable {
    case fast
    case quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast:
            return "Rapide"
        case .quality:
            return "Optimale"
        }
    }

    var sttModel: String {
        switch self {
        case .fast:
            return "mlx-community/whisper-small-mlx"
        case .quality:
            return "mlx-community/whisper-medium-mlx"
        }
    }

    var polishModel: String {
        switch self {
        case .fast:
            return "mlx-community/gemma-4-e2b-it-4bit"
        case .quality:
            return "mlx-community/gemma-4-e4b-it-4bit"
        }
    }

    var bundledModelsDescription: String {
        switch self {
        case .fast:
            return "Whisper Small · Gemma 4 2B"
        case .quality:
            return "Whisper Medium · Gemma 4 4B"
        }
    }
}

struct TierInstallStatus: Identifiable, Equatable {
    let tier: ModelTier
    let sttInstalled: Bool
    let polishInstalled: Bool

    var id: String { tier.id }

    var isFullyInstalled: Bool {
        sttInstalled && polishInstalled
    }

    var hasAnyInstalled: Bool {
        sttInstalled || polishInstalled
    }

    var statusLabel: String {
        if isFullyInstalled {
            return "Téléchargé"
        }
        if hasAnyInstalled {
            return "Partiel"
        }
        return "Absent"
    }
}

enum OverlayState: Equatable {
    case hidden
    case listening
    case processing
    case error(String)
}

enum DictationError: LocalizedError {
    case inferenceNotReady
    case emptyAudio
    case emptyTranscript
    case injectionFailed

    var errorDescription: String? {
        switch self {
        case .inferenceNotReady:
            return "Le serveur d'inférence n'est pas prêt."
        case .emptyAudio:
            return "Aucun audio capturé."
        case .emptyTranscript:
            return "Aucune parole détectée."
        case .injectionFailed:
            return "Impossible d'insérer le texte."
        }
    }
}

struct AppSettings {
    var tier: ModelTier
    var hotkeyModifiers: UInt
    var hotkeyKeyCode: UInt16
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        tier: .quality,
        hotkeyModifiers: UInt(NSEvent.ModifierFlags.option.rawValue),
        hotkeyKeyCode: 49,
        hasCompletedOnboarding: false
    )
}
