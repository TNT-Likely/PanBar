import Foundation

/// GBK (GB18030) 解码助手。腾讯财经、新浪财经接口返回 GBK 编码。
enum GBKDecoder {
    /// CFStringEncoding 的 GB_18030_2000 raw value。
    private static let gb18030: UInt32 = 0x80000632

    static var encoding: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(gb18030))
    }

    static func decode(_ data: Data) -> String? {
        String(data: data, encoding: encoding)
    }
}
