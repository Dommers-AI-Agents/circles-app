import CoreNFC
import Foundation

/// Writes a store's sticker link onto an NFC tag, reads one back, or locks
/// one for good (Manage Store → NFC stickers, 2026-11-01). One iOS scan
/// sheet per call; the result comes back on the main queue.
///
/// Locking is its own step and only locks a sticker that already holds the
/// expected link, so a wrong sticker can never be frozen by mistake.
final class NFCStickerSession: NSObject {

    enum Mode {
        case write(URL)
        case read
        case lock(expected: URL)
    }

    enum Outcome {
        case written
        /// The first link on the sticker; nil = blank or not a link
        case read(String?)
        case locked
    }

    enum Failure: LocalizedError {
        /// The person closed the scan sheet or it timed out: say nothing
        case cancelled
        case unavailable
        case message(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return nil
            case .unavailable: return "This iPhone can't write NFC stickers. It needs an iPhone 7 or newer (iPads have no NFC)."
            case .message(let text): return text
            }
        }
    }

    static var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    /// The running session keeps itself alive until it finishes
    private static var current: NFCStickerSession?

    private let mode: Mode
    private let completion: (Result<Outcome, Failure>) -> Void
    private var session: NFCNDEFReaderSession?
    private var finished = false

    private init(mode: Mode, completion: @escaping (Result<Outcome, Failure>) -> Void) {
        self.mode = mode
        self.completion = completion
    }

    static func start(_ mode: Mode, prompt: String, completion: @escaping (Result<Outcome, Failure>) -> Void) {
        guard isAvailable else {
            completion(.failure(.unavailable))
            return
        }
        current?.session?.invalidate()
        let runner = NFCStickerSession(mode: mode, completion: completion)
        let session = NFCNDEFReaderSession(delegate: runner, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = prompt
        runner.session = session
        current = runner
        session.begin()
    }

    private func finish(_ result: Result<Outcome, Failure>) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async {
            self.completion(result)
            if NFCStickerSession.current === self { NFCStickerSession.current = nil }
        }
    }

    /// Ends the sheet with a message and reports the failure
    private func fail(_ session: NFCNDEFReaderSession, _ text: String) {
        session.invalidate(errorMessage: text)
        finish(.failure(.message(text)))
    }

    private func succeed(_ session: NFCNDEFReaderSession, _ text: String, _ outcome: Outcome) {
        session.alertMessage = text
        session.invalidate()
        finish(.success(outcome))
    }

    private static func firstLink(_ message: NFCNDEFMessage?) -> String? {
        message?.records.lazy.compactMap { $0.wellKnownTypeURIPayload()?.absoluteString }.first
    }

    private func handle(_ tag: NFCNDEFTag, in session: NFCNDEFReaderSession) {
        tag.queryNDEFStatus { [self] status, capacity, error in
            if error != nil { return fail(session, "Couldn't read the sticker. Hold the top of the phone still on it and try again.") }
            if status == .notSupported {
                return fail(session, "This sticker can't hold a link. Use NTAG213, 215 or 216 NFC stickers.")
            }
            switch mode {
            case .read:
                tag.readNDEF { message, _ in
                    let link = Self.firstLink(message)
                    self.succeed(session, link == nil ? "This sticker is blank." : "Got it.", .read(link))
                }

            case .write(let url):
                guard status == .readWrite else {
                    return fail(session, "This sticker is locked, so it can't be changed. Use a new sticker.")
                }
                guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                    return fail(session, "Couldn't make the link for this sticker.")
                }
                let message = NFCNDEFMessage(records: [payload])
                guard message.length <= capacity else {
                    return fail(session, "This sticker is too small for the link. Use NTAG213 or bigger.")
                }
                tag.writeNDEF(message) { error in
                    if error != nil { return self.fail(session, "Writing didn't finish. Hold still and try again.") }
                    self.succeed(session, "Sticker written.", .written)
                }

            case .lock(let expected):
                if status == .readOnly { return succeed(session, "This sticker is already locked.", .locked) }
                tag.readNDEF { message, _ in
                    guard Self.firstLink(message) == expected.absoluteString else {
                        return self.fail(session, "This sticker holds a different link. Write it first, then lock it.")
                    }
                    tag.writeLock { error in
                        if error != nil { return self.fail(session, "Locking didn't finish. Try again.") }
                        self.succeed(session, "Sticker locked.", .locked)
                    }
                }
            }
        }
    }
}

extension NFCStickerSession: NFCNDEFReaderSessionDelegate {

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    // Required, but never called: `didDetect tags` below takes over
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "More than one sticker is close by. Hold the phone to just one."
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { session.restartPolling() }
            return
        }
        session.connect(to: tag) { [self] error in
            if error != nil { return fail(session, "Couldn't connect to the sticker. Try again.") }
            handle(tag, in: session)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Our own invalidate() lands here too, after finish() already ran
        let code = (error as? NFCReaderError)?.code
        if code == .readerSessionInvalidationErrorUserCanceled || code == .readerSessionInvalidationErrorSessionTimeout {
            finish(.failure(.cancelled))
        } else {
            finish(.failure(.message(error.localizedDescription)))
        }
    }
}
