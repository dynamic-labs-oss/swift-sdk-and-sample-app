import SwiftUI
import DynamicSDKSwift

struct SignMessageScreen: View {
  let wallet: BaseWallet

  @State private var message: String = "Hello from Dynamic SDK!"
  @State private var signedMessage: String?
  @State private var errorMessage: String?
  @State private var isLoading: Bool = false

  // Signing-quorum demo state
  @State private var chainName: String = "EVM"
  @State private var approvalQuorum: [String: Any]?
  @State private var consentContext: SigningConsentRequiredContext?
  @State private var quorumStatus: String?

  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // Info Card
        InfoCard(
          title: "Sign Message",
          content: "Sign a message with your wallet. This is a common way to prove ownership of a wallet address."
        )

        // Message Input
        TextFieldWithLabel(
          label: "Message",
          placeholder: "Enter message to sign",
          text: $message
        )

        quorumSection()

        // Sign Button
        PrimaryButton(
          title: isLoading ? "Signing..." : (approvalQuorum != nil ? "Sign with approval" : "Sign Message"),
          action: { signMessage() },
          isLoading: isLoading
        )

        // Error Message
        if let error = errorMessage {
          ErrorMessageView(message: error)
        }

        // Success Message
        if let signed = signedMessage {
          SuccessMessageView(
            message: signed
          )
        }
      }
      .padding()
    }
    .navigationTitle("Sign Message")
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Signing quorum

  @ViewBuilder
  private func quorumSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Signing quorum")
          .font(.headline)
          .fontWeight(.bold)

        Text("For a business-account governed wallet: prepare the approval first, then sign. If the quorum isn't met yet, the SDK throws signingConsentRequired — the intent/consent path is handled below.")
          .font(.caption)
          .foregroundColor(.secondary)

        TextFieldWithLabel(
          label: "WaaS chain name",
          placeholder: "EVM",
          text: $chainName
        )

        PrimaryButton(
          title: "Prepare quorum approval",
          action: { prepareApproval() },
          isLoading: isLoading,
          isDisabled: wallet.id == nil
        )

        if let status = quorumStatus {
          Text(status)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if let context = consentContext {
          consentPanel(context)
        }
      }
    }
  }

  @ViewBuilder
  private func consentPanel(_ context: SigningConsentRequiredContext) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Signing consent required")
        .font(.subheadline)
        .fontWeight(.semibold)

      InfoRow(label: "Reason", value: context.reason?.rawValue ?? "unknown")
      if let proposalId = context.proposalId {
        InfoRow(label: "Proposal", value: proposalId)
      }
      if let requirements = context.approvalRequirements {
        ForEach(requirements, id: \.requirementId) { requirement in
          Text("\(requirement.action): \(requirement.approved)/\(requirement.required)\(requirement.satisfied ? " ✓" : "")")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      if context.reason == .intentRequired {
        PrimaryButton(
          title: "Sign intent & retry",
          action: { signIntentAndRetry(context) },
          isLoading: isLoading
        )
      }

      if context.reason == .approvalsRequired {
        Text("Have the other signers approve the proposal (Business Accounts screen → Proposals), then resume it.")
          .font(.caption)
          .foregroundColor(.secondary)
        PrimaryButton(
          title: "Resume signing proposal",
          action: { resumeProposal(context) },
          isLoading: isLoading
        )
      }
    }
  }

  private func prepareApproval() {
    guard let walletId = wallet.id else { return }
    isLoading = true
    errorMessage = nil
    quorumStatus = nil

    Task {
      do {
        let approval = try await DynamicSDK.instance().businessAccounts.prepareSigningQuorumApproval(
          walletId: walletId,
          chainName: chainName,
          operation: ["kind": "message", "message": message]
        )
        await MainActor.run {
          approvalQuorum = approval
          quorumStatus = approval != nil
            ? "Approval prepared — tap \"Sign with approval\"."
            : "Wallet is not governed by a business account; approval not needed."
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  private func signMessage() {
    isLoading = true
    errorMessage = nil
    signedMessage = nil
    consentContext = nil

    Task {
      do {
        let signed = try await DynamicSDK.instance().wallets.signMessage(
          wallet: wallet,
          message: message,
          approvalQuorum: approvalQuorum
        )

        await MainActor.run {
          signedMessage = signed
          isLoading = false
        }
      } catch DynamicSDKError.signingConsentRequired(let context) {
        await MainActor.run {
          consentContext = context
          quorumStatus = context.reason == .intentRequired
            ? "INTENT_REQUIRED — sign the intent with your session key, then retry."
            : "APPROVALS_REQUIRED — proposal \(context.proposalId ?? "?") needs member approvals."
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  private func signIntentAndRetry(_ context: SigningConsentRequiredContext) {
    guard let intent = context.intent else {
      errorMessage = "Consent response did not include an intent to sign."
      return
    }
    isLoading = true
    errorMessage = nil

    Task {
      do {
        let signed = try await DynamicSDK.instance().businessAccounts.signSigningQuorumIntent(
          intent: intent,
          request: verificationRequest(from: intent),
          preparedPayload: preparedPayload(from: intent)
        )
        await MainActor.run {
          approvalQuorum = signed.toDict()
          consentContext = nil
          isLoading = false
        }
        signMessage()
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  private func resumeProposal(_ context: SigningConsentRequiredContext) {
    guard let proposalId = context.proposalId else { return }
    isLoading = true
    errorMessage = nil

    Task {
      do {
        let businessAccountId: String
        if let id = context.intent?["businessAccountId"] as? String {
          businessAccountId = id
        } else {
          businessAccountId = try await findBusinessAccountId(for: proposalId)
        }
        let signature = try await DynamicSDK.instance().businessAccounts.resumeSigningProposal(
          businessAccountId: businessAccountId,
          proposalId: proposalId
        )
        await MainActor.run {
          signedMessage = signature
          consentContext = nil
          isLoading = false
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  private func findBusinessAccountId(for proposalId: String) async throws -> String {
    let awaiting = try await DynamicSDK.instance().businessAccounts.listProposalsAwaitingMyApproval()
    guard let proposal = awaiting.first(where: { $0.id == proposalId }) else {
      throw NSError(
        domain: "SignMessageScreen",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not resolve businessAccountId for proposal \(proposalId)"]
      )
    }
    return proposal.businessAccountId
  }

  /// Rebuilds the verification request `signSigningQuorumIntent` checks the
  /// intent against — identity fields live on the intent, operation fields on
  /// `intent.operation`.
  private func verificationRequest(from intent: [String: Any]) -> [String: Any] {
    let operation = intent["operation"] as? [String: Any] ?? [:]
    var request: [String: Any] = [:]
    for key in ["accountAddress", "businessAccountId", "completeBy", "initiatorUserId"] {
      request[key] = intent[key]
    }
    for key in ["chainName", "kind", "message", "typedData", "rawSign", "chainId", "refreshLimits"] {
      request[key] = operation[key]
    }
    return request
  }

  private func preparedPayload(from intent: [String: Any]) -> String? {
    let operation = intent["operation"] as? [String: Any]
    return operation?["payload"] as? String
  }
}
