import Foundation

enum ArtifactItem: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            self = .other
        }
    }
}

struct CaskJSON: Decodable {
    let data: [CaskItem]

    struct CaskItem: Decodable {
        let name: [String]
        let url: URL
        let version: String
        let sha256: String
        let artifacts: [Artifact]
        let homepage: URL
        
        struct Artifact: Decodable {
            let app: [ArtifactItem]?
            let pkg: [ArtifactItem]?
        }
    }
}

class Provider {
    let json = {
        let path = Bundle.main.path(forResource: "cask", ofType: "json")!
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        return try! JSONDecoder().decode(CaskJSON.self, from: data).data
    }()
}
