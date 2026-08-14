//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import ArgumentParser
import Foundation
import SwiftOCA
import SwiftOCASecure

/// Everything to do with TLS: whether to use it, which credential to present, and how much of
/// the server's certificate chain to believe.
struct TLSOptions: ParsableArguments {
  @Flag(
    name: [.customShort("S"), .long],
    help: "Use TLS over TCP; combine with -U for DTLS over UDP"
  )
  var tls = false

  @Option(name: [.customShort("I"), .long], help: "TLS PSK identity (default: OCA-PSK)")
  var pskIdentity: String?

  @Option(name: [.customShort("K"), .long], help: "TLS PSK key, hex-encoded")
  var pskKey: String?

  @Option(name: .long, help: "TLS client certificate PEM file")
  var cert: String?

  @Option(name: .long, help: "TLS client private key PEM file")
  var key: String?

  @Option(name: .long, help: "TLS client PKCS#12 bundle path")
  var pkcs12: String?

  @Option(
    name: .long,
    help: "PKCS#12 bundle password (env: OCACLI_PKCS12_PASSWORD; prompted if omitted)"
  )
  var pkcs12Password: String?

  @Flag(
    name: [.customShort("k"), .long],
    help: "Disable TLS server certificate verification (cert credentials only; for testing)"
  )
  var insecure = false

  @Option(name: .long, help: "PEM CA bundle for TLS server-cert verification")
  var cacert: String?

  @Option(name: .long, help: "PEM CRL bundle for TLS revocation checking")
  var crlFile: String?

  @Flag(name: .long, help: "Enable TLS revocation checking against leaf certificate")
  var checkRevocation = false

  @Flag(name: .long, help: "Enable TLS revocation checking across the full chain")
  var checkRevocationAll = false

  var trustRoots: Ocp1TLSTrustRoots? {
    cacert.map { .caFile($0) }
  }

  /// The credential families that can be given on a command line. The library accepts others
  /// (raw in-memory PEM, platform-native identities) that aren't meaningful here.
  private var hasPSK: Bool {
    pskKey != nil
  }

  private var hasCertificate: Bool {
    cert != nil || key != nil
  }

  private var hasPKCS12: Bool {
    pkcs12 != nil
  }

  func validate() throws {
    guard tls else {
      let dependent = hasPSK || hasCertificate || hasPKCS12 || pskIdentity != nil ||
        pkcs12Password != nil || cacert != nil || insecure || crlFile != nil ||
        checkRevocation || checkRevocationAll
      if dependent {
        throw ValidationError("The TLS options require --tls.")
      }
      return
    }

    switch [hasPSK, hasCertificate, hasPKCS12].filter({ $0 }).count {
    case 1:
      break
    case 0:
      throw ValidationError(
        "--tls requires a credential: --psk-key, --cert with --key, or --pkcs12."
      )
    default:
      throw ValidationError("--psk-key, --cert/--key and --pkcs12 are mutually exclusive.")
    }

    if hasCertificate, cert == nil || key == nil {
      throw ValidationError("--cert and --key must be supplied together.")
    }

    if let pskKey {
      guard let keyBytes = Data(hex: pskKey) else {
        throw ValidationError("--psk-key must be a hex string.")
      }
      // the library enforces this too, but saying so here is clearer than the parameter error
      // it would otherwise throw at connect time
      guard keyBytes.count >= OcaMinimumPreSharedKeyLength else {
        throw ValidationError(
          "--psk-key must be at least \(OcaMinimumPreSharedKeyLength) bytes, but is \(keyBytes.count)."
        )
      }
    }
  }

  /// The credential to present, or nil if TLS was not asked for. Validation has already
  /// established that exactly one family was given and that it is well formed.
  func credential() throws -> Ocp1TLSCredential? {
    guard tls else { return nil }

    if let pskKey, let keyBytes = Data(hex: pskKey) {
      return .preSharedKey(
        identity: pskIdentity ?? OcaPreSharedKeyIdentityHint,
        key: keyBytes
      )
    }

    if let cert, let key {
      return .certificateFile(certPath: cert, keyPath: key)
    }

    guard let pkcs12 else { throw Ocp1Error.status(.parameterError) }
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: pkcs12))
    } catch {
      throw ValidationError("Could not read the PKCS#12 file at \(pkcs12): \(error).")
    }
    return .pkcs12(data: data, password: pkcs12BundlePassword)
  }

  /// Revocation is off by default; a CRL alone is enough to opt in, as it would otherwise sit
  /// unused.
  var revocationOptions: Ocp1TLSRevocationOptions {
    var flags: Ocp1TLSRevocationOptions.Flags = []
    if checkRevocation || crlFile != nil { flags.insert(.enabled) }
    if checkRevocationAll { flags.insert([.enabled, .checkChain]) }
    return Ocp1TLSRevocationOptions(flags: flags, crls: crlFile.map { .crlFile($0) })
  }

  /// A PKCS#12 password the user need not put on the command line, where it would be visible in
  /// `ps` and in shell history: the option wins, then the environment, then a prompt. Nil means
  /// no password, which only an unencrypted bundle will accept.
  private var pkcs12BundlePassword: String? {
    if let pkcs12Password { return pkcs12Password }
    if let environment = ProcessInfo.processInfo.environment["OCACLI_PKCS12_PASSWORD"] {
      return environment
    }
    // without a terminal getpass would either block or echo, so let the library try the bundle
    // without a password and fail cleanly
    guard isatty(STDIN_FILENO) != 0 else { return nil }
    guard let prompted = getpass("PKCS#12 password: ") else { return nil }
    let password = String(cString: prompted)
    return password.isEmpty ? nil : password
  }
}
