//
//  CryptoUtils.swift
//  abook-reaper
//
//  Pure Swift reimplementation of the CryptoJS AES decryption
//  used by akniga.org to encrypt the m3u8 URL in the `hres` field.
//

import Foundation
import CommonCrypto

enum CryptoUtils {

    // MARK: - Password generation (mirrors plh.assets())

    /// Primary decryption password: base chars + transformed PI digits
    static func primaryPassword() -> String {
        // plh.base() = String.fromCharCode(0x79,0x6d,0x58,0x45,0x4b,0x7a,0x76,0x55,0x6b,0x75,0x6f,0x35,0x47,0x30)
        let base = "ymXEKzvUkuo5G0"

        // Transform PI digits: even→letter (0→A,2→B,4→C,6→D,8→E), odd→digit, '.'→'.'
        let piStr = String("\(Double.pi)".prefix(18)) // "3.141592653589793"
        let evenMap: [Int: Character] = [0: "A", 2: "B", 4: "C", 6: "D", 8: "E"]

        var pw = base
        for ch in piStr {
            if let d = ch.wholeNumberValue {
                if d % 2 == 0 {
                    pw.append(evenMap[d]!)
                } else {
                    pw.append(String(d))
                }
            } else {
                pw.append(ch) // '.'
            }
        }
        return pw
    }

    /// Fallback password: plh.assets2()
    static let fallbackPassword = "EKxtcg46V"

    // MARK: - CryptoJS-compatible AES decrypt

    /// Decrypt an `hres` JSON string → plaintext URL string.
    /// Format: {"ct":"<base64>","iv":"<hex>","s":"<hex>"}
    /// Uses OpenSSL-compatible EVP_BytesToKey KDF.
    static func decryptHres(_ hres: String) -> String? {
        // Try primary password first, then fallback
        if let result = decryptWithPassword(hres, password: primaryPassword()) {
            return result
        }
        return decryptWithPassword(hres, password: fallbackPassword)
    }

    private static func decryptWithPassword(_ hres: String, password: String) -> String? {
        guard let data = hres.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let ctBase64 = json["ct"],
              let ciphertext = Data(base64Encoded: ctBase64),
              let saltHex = json["s"]
        else { return nil }

        let salt = hexToBytes(saltHex)
        guard salt.count == 8 else { return nil }

        // CryptoJS uses EVP_BytesToKey with MD5, 1 iteration, to derive key+iv
        let passwordBytes = Array(password.utf8)
        let (key, iv) = evpBytesToKey(password: passwordBytes, salt: salt, keyLen: 32, ivLen: 16)

        // If explicit IV is provided in json, use it instead
        let finalIV: [UInt8]
        if let ivHex = json["iv"] {
            finalIV = hexToBytes(ivHex)
        } else {
            finalIV = iv
        }

        guard let plaintext = aesDecrypt(data: Array(ciphertext), key: key, iv: finalIV) else {
            return nil
        }

        return String(bytes: plaintext, encoding: .utf8)
    }

    // MARK: - EVP_BytesToKey (OpenSSL KDF used by CryptoJS)

    /// Derives key and IV from password+salt using MD5, matching CryptoJS default.
    private static func evpBytesToKey(password: [UInt8], salt: [UInt8], keyLen: Int, ivLen: Int) -> ([UInt8], [UInt8]) {
        var derived = [UInt8]()
        var block = [UInt8]()
        let totalNeeded = keyLen + ivLen

        while derived.count < totalNeeded {
            var input = block + password + salt
            block = md5(input)
            derived.append(contentsOf: block)
            input = []
        }

        let key = Array(derived[0..<keyLen])
        let iv = Array(derived[keyLen..<keyLen + ivLen])
        return (key, iv)
    }

    private static func md5(_ data: [UInt8]) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBufferPointer { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest
    }

    // MARK: - AES-256-CBC decrypt

    private static func aesDecrypt(data: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8]? {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var bytesDecrypted = 0

        let status = key.withUnsafeBufferPointer { keyPtr in
            iv.withUnsafeBufferPointer { ivPtr in
                data.withUnsafeBufferPointer { dataPtr in
                    buffer.withUnsafeMutableBufferPointer { bufPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            bufPtr.baseAddress, bufferSize,
                            &bytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return Array(buffer[0..<bytesDecrypted])
    }

    // MARK: - Hex helpers

    private static func hexToBytes(_ hex: String) -> [UInt8] {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }
}
