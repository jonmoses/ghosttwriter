import Foundation

/// Kitty graphics protocol escapes.
public enum KittyImage {
    /// An escape that tells a Kitty-compatible terminal to read the PNG at
    /// `path` from disk and display it (a=T, f=100, t=f, base64 path).
    public static func escape(forPNGAt path: String) -> String {
        let b64 = Data(path.utf8).base64EncodedString()
        return "\u{1b}_Ga=T,f=100,t=f;\(b64)\u{1b}\\"
    }
}
