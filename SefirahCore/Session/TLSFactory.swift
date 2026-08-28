import Foundation
import Network
import Security

enum TLSTrustPolicy: Sendable {
    case stash
    case pin(Data)
}

enum TLSFactory {
    static func parameters(
        identity: SecIdentity,
        policy: TLSTrustPolicy,
        stash: CertificateStash,
        queue: DispatchQueue
    ) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, true)
        guard let secIdentity = sec_identity_create(identity) else {
            return NWParameters(tls: tls)
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)

        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let der = PeerCertificate.der(from: secTrust) else {
                complete(false)
                return
            }
            switch policy {
            case .stash:
                stash.stash(certificateDER: der)
                complete(true)
            case .pin(let expected):
                let ok = der == expected
                if ok {
                    stash.stash(certificateDER: der)
                }
                complete(ok)
            }
        }, queue)

        let parameters = NWParameters(tls: tls)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        // Android reconnects over IPv4 (QR + NSD strip IPv6). Default NWListener
        // on macOS binds IPv6-only (`*:5150`), so IPv4 SYNs never complete.
        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        return parameters
    }
}
