import Foundation
import Combine
import DynamicSDKSwift

@MainActor
final class WalletDetailsViewModel: ObservableObject {
  @Published var balance: String?
  @Published var networkDescription: String?
  @Published var isLoadingBalance: Bool = false
  @Published var isLoadingNetwork: Bool = false
  @Published var errorMessage: String?
  @Published var delegationStatus: WalletDelegatedStatus?
  @Published var isDelegationLoading: Bool = false
  @Published var feedbackMessage: String?

  private let sdk = DynamicSDK.instance()
  private let wallet: BaseWallet
  private var cancellables = Set<AnyCancellable>()

  init(wallet: BaseWallet) {
    self.wallet = wallet
    setupDelegationObserver()
  }

  private func setupDelegationObserver() {
    sdk.wallets.delegatedAccessChanges
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateDelegationStatus()
      }
      .store(in: &cancellables)
  }

  private func updateDelegationStatus() {
    guard let walletId = wallet.id else { return }
    delegationStatus = sdk.wallets.getDelegationStatusForWallet(walletId)
  }

  func refresh() {
    errorMessage = nil
    isLoadingBalance = true
    isLoadingNetwork = true
    updateDelegationStatus()

    Task { @MainActor in
      // Balance
      do {
        balance = try await sdk.wallets.getBalance(wallet: wallet)
      } catch {
        Logger.debug("[WalletDetails] getBalance error: \(error)")
      }
      isLoadingBalance = false

      // Network
      do {
        let net = try await sdk.wallets.getNetwork(wallet: wallet)
        let rawId = Self.normalizeAny(net.value.value)
        networkDescription = Self.resolveNetworkDisplay(
          walletChain: wallet.chain,
          rawId: rawId,
          networks: sdk.networks.networksForChain(wallet.chain)
        )
      } catch {
        Logger.debug("[WalletDetails] getNetwork error: \(error)")
      }
      isLoadingNetwork = false
    }
  }

  func setPrimary() {
    guard let id = wallet.id else { return }
    errorMessage = nil
    Task { @MainActor in
      do {
        try await sdk.wallets.setPrimary(walletId: id)
      } catch {
        errorMessage = "Failed to set primary wallet: \(error)"
      }
    }
  }

  func revealPrivateKey() {
    errorMessage = nil
    Task { @MainActor in
      do {
        try await sdk.ui.revealEmbeddedWalletPrivateKey()
      } catch {
        errorMessage = "Failed to reveal private key: \(error)"
      }
    }
  }

  func enableDelegation() {
    errorMessage = nil
    isDelegationLoading = true
    Task { @MainActor in
      do {
        let chainEnum: ChainEnum = wallet.chain.uppercased() == "EVM" ? .evm : .sol
        try await sdk.wallets.waas.delegation.delegateKeyShares(
          wallets: [
            DelegationWalletIdentifier(
              chainName: chainEnum,
              accountAddress: wallet.address
            )
          ]
        )
        feedbackMessage = "Delegated access enabled successfully"
      } catch {
        errorMessage = "Failed to enable delegation: \(error)"
      }
      isDelegationLoading = false
    }
  }

  func revokeDelegation() {
    errorMessage = nil
    isDelegationLoading = true
    Task { @MainActor in
      do {
        let chainEnum: ChainEnum = wallet.chain.uppercased() == "EVM" ? .evm : .sol
        try await sdk.wallets.waas.delegation.revokeDelegation(
          wallets: [
            DelegationWalletIdentifier(
              chainName: chainEnum,
              accountAddress: wallet.address
            )
          ]
        )
        feedbackMessage = "Delegated access revoked successfully"
      } catch {
        errorMessage = "Failed to revoke delegation: \(error)"
      }
      isDelegationLoading = false
    }
  }

  private static func normalizeAny(_ value: Any) -> String {
    if let s = value as? String { return s }
    if let i = value as? Int { return String(i) }
    if let d = value as? Double { return String(Int(d)) }
    return String(describing: value)
  }

  private static func resolveNetworkDisplay(
    walletChain: String,
    rawId: String,
    networks: [GenericNetwork]
  ) -> String {
    let chain = walletChain.uppercased()

    if networks.isEmpty {
      return rawId
    }

    for network in networks {
      if chain == "EVM" {
        if normalizeAny(network.chainId.value) == rawId {
          return "\(network.name) (\(rawId))"
        }
      } else {
        let matchesNetworkId = normalizeAny(network.networkId.value) == rawId
        let matchesChainId = normalizeAny(network.chainId.value) == rawId
        if matchesNetworkId || matchesChainId {
          return "\(network.name) (\(rawId))"
        }
      }
    }

    return "unresolved (\(rawId))"
  }
}
