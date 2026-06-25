import Foundation

enum InferenceEvent: Decodable, Equatable {
    case progress(stage: String, model: String, percent: Double, requestID: String?)
    case error(message: String, requestID: String?)
    case pingResult(ok: Bool, requestID: String?)
    case loadModelsResult(tier: String?, requestID: String?)
    case transcribeResult(text: String, requestID: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case message
        case stage
        case model
        case percent
        case tier
        case ok
        case text
        case requestID = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let requestID = try container.decodeIfPresent(String.self, forKey: .requestID)

        switch type {
        case "progress":
            self = .progress(
                stage: try container.decode(String.self, forKey: .stage),
                model: try container.decode(String.self, forKey: .model),
                percent: try container.decode(Double.self, forKey: .percent),
                requestID: requestID
            )
        case "error":
            self = .error(
                message: try container.decode(String.self, forKey: .message),
                requestID: requestID
            )
        case "result":
            let command = try container.decode(String.self, forKey: .command)
            switch command {
            case "ping":
                self = .pingResult(
                    ok: try container.decode(Bool.self, forKey: .ok),
                    requestID: requestID
                )
            case "load_models":
                self = .loadModelsResult(
                    tier: try container.decodeIfPresent(String.self, forKey: .tier),
                    requestID: requestID
                )
            case "transcribe":
                self = .transcribeResult(
                    text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                    requestID: requestID
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .command,
                    in: container,
                    debugDescription: "Unknown result command: \(command)"
                )
            }
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown inference event type: \(type)"
            )
        }
    }
}

extension InferenceEvent {
    var requestID: String? {
        switch self {
        case .progress(_, _, _, let requestID),
             .error(_, let requestID),
             .pingResult(_, let requestID),
             .loadModelsResult(_, let requestID),
             .transcribeResult(_, let requestID):
            return requestID
        }
    }

    static func decodeLine(_ line: String) -> InferenceEvent? {
        guard !line.isEmpty, let lineData = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InferenceEvent.self, from: lineData)
    }
}
