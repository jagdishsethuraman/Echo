// Verify the generated feed targets this release and the embedded trust key accepts its archive.
import CryptoKit
import Foundation

let args = CommandLine.arguments
let feed = try XMLDocument(contentsOf: URL(fileURLWithPath: args[1]))
let archive = URL(fileURLWithPath: args[2])
let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
guard let item = try feed.nodes(forXPath: "/rss/channel/item").first as? XMLElement,
      let enclosure = item.elements(forName: "enclosure").first,
      let url = enclosure.attribute(forName: "url")?.stringValue,
      url == "https://github.com/jagdishsethuraman/Echo/releases/download/v\(args[4])/\(archive.lastPathComponent)",
      item.elements(forLocalName: "version", uri: "http://www.andymatuschak.org/xml-namespaces/sparkle").first?.stringValue == args[4],
      let signature = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue.flatMap({ Data(base64Encoded: $0) }),
      let publicBytes = Data(base64Encoded: args[3]),
      try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes).isValidSignature(signature, for: bytes)
else { fatalError("Release metadata or Sparkle archive signature does not match") }
