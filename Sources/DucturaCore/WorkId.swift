import Foundation

/// ID rada po pravilu ugovora S-1H.1-c, isto kao serverski `isWorkId` i
/// `workIdFromPath` (ductura/server `contracts/work-id.ts`). ID je neproziran
/// podatak: navodnici, `;` i `../` prolaze. Pravilo čita samo Unicode scalare.
public enum WorkId {
    /// Najdulji ID, u scalarima (`length(id)` u CHECK-u baze).
    public static let maxLength = 256

    /// Skup koji JS `trim()` skida: WhiteSpace (TAB, VT, FF, U+FEFF, Zs) i LineTerminator.
    /// Izričit popis, jer se `CharacterSet.whitespaces` razlikuje po platformama.
    static let trimmed: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
        0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
    ]

    /// 1 do 256 scalara, bez rubnog razmaka i bez kontrolnih znakova (C0 i C1).
    public static func isValid(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first, let last = scalars.last,
              !trimmed.contains(first.value), !trimmed.contains(last.value) else { return false }
        if scalars.contains(where: { $0.properties.generalCategory == .control }) { return false }
        return scalars.count <= maxLength
    }

    /// ID iz jednog sirovog (još kodiranog) segmenta putanje ili `nil`. Dekodira točno jednom.
    public static func fromPathSegment(_ segment: String) -> String? {
        guard let decoded = percentDecode(segment), isValid(decoded) else { return nil }
        return decoded
    }

    /// URL rada `<adresa>#/doc/<ID>` (adresa iz paketa, zadano `/app/`), s kodiranim ID-om;
    /// `nil` za neispravan ID.
    public static func documentURL(web: WebAddress, id: String?) -> URL? {
        guard let id, isValid(id) else { return nil }
        return URL(string: web.url + "#/doc/" + encode(id))
    }

    /// Sve osim RFC 3986 unreserved znakova postaje `%XX` po UTF-8 bajtu.
    static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E:
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// Vlastito dekodiranje (Foundation na Linuxu gubi početni U+FEFF). Slomljen
    /// `%` ili neispravan UTF-8 (overlong, surogat, izvan raspona) daje `nil`.
    static func percentDecode(_ value: String) -> String? {
        var bytes: [UInt8] = []
        var input = Array(value.utf8)[...]
        while let byte = input.popFirst() {
            guard byte == 0x25 else { bytes.append(byte); continue }
            guard input.count >= 2, let hi = hex(input.removeFirst()), let lo = hex(input.removeFirst())
            else { return nil }
            bytes.append(hi << 4 | lo)
        }
        let decoded = String(decoding: bytes, as: UTF8.self)
        return Array(decoded.utf8) == bytes ? decoded : nil
    }

    static func hex(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x37
        case 0x61...0x66: return c - 0x57
        default: return nil
        }
    }
}
