import Foundation

enum StageJSONParser {
    static func parseStage1(_ raw: String) throws -> Stage1Payload {
        let data = Data(raw.utf8)
        return try JSONDecoder().decode(Stage1Payload.self, from: data)
    }

    static func parseStage2(_ raw: String) throws -> Stage2Payload {
        let data = Data(raw.utf8)
        return try JSONDecoder().decode(Stage2Payload.self, from: data)
    }
}
