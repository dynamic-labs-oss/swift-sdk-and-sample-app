import SwiftUI
import DynamicSDKSwift

struct WalletDetailsScreen: View {
  let wallet: BaseWallet
  @Environment(\.colorScheme) var colorScheme
  @State private var showCopiedAlert = false
  @State private var feedbackLabel: String?
  @StateObject private var vm: WalletDetailsViewModel
  
  init(wallet: BaseWallet) {
    self.wallet = wallet
    self._vm = StateObject(wrappedValue: WalletDetailsViewModel(wallet: wallet))
  }
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Wallet Card
        WalletDetailCard(
          wallet: wallet,
          balance: vm.balance,
          network: vm.networkDescription,
          isLoadingBalance: vm.isLoadingBalance,
          isLoadingNetwork: vm.isLoadingNetwork
        )

        // Delegation Section
        if let status = vm.delegationStatus {
          DelegationSectionView(
            status: status,
            isLoading: vm.isDelegationLoading,
            onEnable: { vm.enableDelegation() },
            onRevoke: { vm.revokeDelegation() }
          )
          .padding(.horizontal)
        }

        // Feedback message
        if let feedback = vm.feedbackMessage ?? feedbackLabel {
          Text(feedback)
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal)
        }
        
        // Copy Address Button
        Button(action: {
          UIPasteboard.general.string = wallet.address
          showCopiedAlert = true
        }) {
          HStack {
            Image(systemName: "doc.on.doc")
            Text("Copy Address")
            Spacer()
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color.blue.opacity(0.1))
          .foregroundColor(.blue)
          .cornerRadius(8)
        }
        .padding(.horizontal)

        // Copy Wallet Details Button
        Button(action: {
          var details = ""
          if let id = wallet.id, !id.isEmpty {
            details += "ID: \(id)\n"
          }
          details += "Address: \(wallet.address)\n"
          details += "Chain: \(wallet.chain)"
          if let publicKey = wallet.publicKey, !publicKey.isEmpty {
            details += "\nPublic Key: \(publicKey)"
          }
          if let name = wallet.walletName, !name.isEmpty {
            details += "\nWallet Name: \(name)"
          }
          if let provider = wallet.walletProvider, !provider.isEmpty {
            details += "\nWallet Provider: \(provider)"
          }
          UIPasteboard.general.string = details
          showCopiedAlert = true
        }) {
          HStack {
            Image(systemName: "doc.on.clipboard")
            Text("Copy Wallet Details")
            Spacer()
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color.blue.opacity(0.1))
          .foregroundColor(.blue)
          .cornerRadius(8)
        }
        .padding(.horizontal)

        // Sign Message Button (for all chains)
        NavigationLink(destination: SignMessageScreen(wallet: wallet)) {
          HStack {
            Image(systemName: "pencil.circle")
            Text("Sign Message")
            Spacer()
            Image(systemName: "chevron.right")
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color.blue.opacity(0.1))
          .foregroundColor(.blue)
          .cornerRadius(8)
        }
        .padding(.horizontal)
        
        if let err = vm.errorMessage {
          ErrorMessageView(message: err)
            .padding(.horizontal)
        }

        if wallet.id != nil {
          Button(action: { vm.setPrimary() }) {
            HStack {
              Image(systemName: "star.fill")
              Text("Set as Primary Wallet")
              Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
          }
          .padding(.horizontal)

          Button(action: { vm.revealPrivateKey() }) {
            HStack {
              Image(systemName: "key.fill")
              Text("Reveal Private Key")
              Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1))
            .foregroundColor(.orange)
            .cornerRadius(8)
          }
          .padding(.horizontal)
        }

        NavigationLink(destination: SwitchNetworkScreen(wallet: wallet)) {
          HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text("Switch Network")
            Spacer()
            Image(systemName: "chevron.right")
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color.blue.opacity(0.1))
          .foregroundColor(.blue)
          .cornerRadius(8)
        }
        .padding(.horizontal)

        NavigationLink(destination: CustomBalanceScreen(wallet: wallet)) {
          HStack {
            Image(systemName: "chart.bar.fill")
            Text("Custom Token Balances")
            Spacer()
            Image(systemName: "chevron.right")
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color.green.opacity(0.1))
          .foregroundColor(.green)
          .cornerRadius(8)
        }
        .padding(.horizontal)

       

        // Chain-specific actions
        if wallet.chain.uppercased() == "EVM" {
          EVMActionsView(wallet: wallet)
        } else if wallet.chain.uppercased() == "SOL" {
          SolanaActionsView(wallet: wallet)
        } else if wallet.chain.uppercased() == "SUI" {
          SuiActionsView(wallet: wallet)
        } else if wallet.chain.uppercased() == "TON" {
          TonActionsView(wallet: wallet)
        } else if wallet.chain.uppercased() == "BTC" {
          BitcoinActionsView(wallet: wallet)
        } else if wallet.chain.uppercased() == "STELLAR" {
          StellarActionsView(wallet: wallet)
        }
        
        Spacer()
      }
      .padding(.vertical)
    }
    .navigationTitle("Wallet Details")
    .navigationBarTitleDisplayMode(.inline)
    .alert("Copied to clipboard", isPresented: $showCopiedAlert) {
      Button("OK", role: .cancel) {}
    }
    .onAppear { vm.refresh() }
  }
}

struct WalletDetailCard: View {
  let wallet: BaseWallet
  let balance: String?
  let network: String?
  let isLoadingBalance: Bool
  let isLoadingNetwork: Bool
  @Environment(\.colorScheme) var colorScheme
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          if let walletName = wallet.walletName {
            Text(walletName)
              .font(.headline)
              .foregroundColor(colorScheme == .dark ? .white : .black)
          }
          Text(wallet.chain.uppercased())
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(4)
        }
        Spacer()
      }
      
      if let walletId = wallet.id, !walletId.isEmpty {
        Text("Wallet ID")
          .font(.caption)
          .foregroundColor(.secondary)
        Text(walletId)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(colorScheme == .dark ? .white : .black)
          .lineLimit(2)
          .truncationMode(.middle)
        Divider().opacity(0.3)
      }

      Text("Address")
        .font(.caption)
        .foregroundColor(.secondary)

      Text(wallet.address)
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .lineLimit(2)
        .truncationMode(.middle)

      Divider().opacity(0.3)
      Text("Current Network")
        .font(.caption)
        .foregroundColor(.secondary)
      if let network, !network.isEmpty {
        Text(network)
          .font(.system(.caption2, design: .monospaced))
          .foregroundColor(colorScheme == .dark ? .white : .black)
          .lineLimit(2)
          .truncationMode(.middle)
      } else if isLoadingNetwork {
        HStack(spacing: 8) {
          ProgressView().scaleEffect(0.9)
          Text("Loading…")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      } else {
        Text("-")
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Divider().opacity(0.3)
      Text("Balance")
        .font(.caption)
        .foregroundColor(.secondary)
      if let balance, !balance.isEmpty {
        Text(balance)
          .font(.system(.caption2, design: .monospaced))
          .foregroundColor(colorScheme == .dark ? .white : .black)
          .lineLimit(2)
          .truncationMode(.middle)
      } else if isLoadingBalance {
        HStack(spacing: 8) {
          ProgressView().scaleEffect(0.9)
          Text("Loading…")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      } else {
        Text("-")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding()
    .background(Color(.systemBackground).opacity(0.8))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(.systemGray4), lineWidth: 1)
    )
    .padding(.horizontal)
  }
}

struct EVMActionsView: View {
  let wallet: BaseWallet
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("EVM Actions")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)
      
      // Sign Transaction
      NavigationLink(destination: EvmSignTransactionScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "signature",
          title: "Sign Transaction"
        )
      }
      .padding(.horizontal)
      
      // Sign Typed Data
      NavigationLink(destination: EvmSignTypedDataScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "doc.text",
          title: "Sign Typed Data"
        )
      }
      .padding(.horizontal)
      
      // Send Transaction
      NavigationLink(destination: EvmSendTransactionScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "paperplane.fill",
          title: "Send Transaction"
        )
      }
      .padding(.horizontal)

      // Send ERC20
      NavigationLink(destination: EvmSendErc20Screen(wallet: wallet)) {
              WalletActionButton(
          icon: "arrow.right.arrow.left",
          title: "Send ERC20"
        )
      }
      .padding(.horizontal)
      
      // Write Contract
      NavigationLink(destination: EvmWriteContractScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "doc.plaintext",
          title: "Write Contract"
        )
      }
      .padding(.horizontal)

      // Earn
      NavigationLink(destination: EarnScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "chart.line.uptrend.xyaxis",
          title: "Earn (Yield Vaults)"
        )
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
  }
}

struct SolanaActionsView: View {
  let wallet: BaseWallet
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Solana Actions")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)
      
      // Sign Message (Solana specific)
      NavigationLink(destination: SolanaSignMessageScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "pencil.circle",
          title: "Sign Message (Solana)"
        )
      }
      .padding(.horizontal)
      
      // Sign Transaction
      NavigationLink(destination: SolanaSignTransactionScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "signature",
          title: "Sign Transaction"
        )
      }
      .padding(.horizontal)
      
      // Send Transaction
      NavigationLink(destination: SolanaSendTransactionScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "paperplane.fill",
          title: "Send Transaction"
        )
      }
      .padding(.horizontal)

      // Send SPL Token
      NavigationLink(destination: SolanaSendSplTokenScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "arrow.right.arrow.left",
          title: "Send SPL Token"
        )
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
  }
}

struct SuiActionsView: View {
  let wallet: BaseWallet

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("SUI Actions")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)

      // Sign Message
      NavigationLink(destination: SuiSignMessageScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "pencil.circle",
          title: "Sign Message"
        )
      }
      .padding(.horizontal)

      // Sign Transaction
      NavigationLink(destination: SuiSignTransactionScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "signature",
          title: "Sign Transaction"
        )
      }
      .padding(.horizontal)

      // Send Transaction
      NavigationLink(destination: SuiSendTransactionScreen(wallet: wallet)) {
              WalletActionButton(
          icon: "paperplane.fill",
          title: "Send Transaction"
        )
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
  }
}

struct TonActionsView: View {
  let wallet: BaseWallet

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("TON Actions")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)

      NavigationLink(destination: TonSignMessageScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "pencil.circle",
          title: "Sign Message"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: TonSendTonScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "paperplane.fill",
          title: "Send TON"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: TonSendJettonScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "arrow.right.arrow.left",
          title: "Send Jetton"
        )
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
  }
}

struct BitcoinActionsView: View {
  let wallet: BaseWallet

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Bitcoin Actions")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)

      NavigationLink(destination: BitcoinSignMessageScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "pencil.circle",
          title: "Sign Message"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: BitcoinSendScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "paperplane.fill",
          title: "Send Bitcoin"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: BitcoinSignPsbtScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "signature",
          title: "Sign PSBT"
        )
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
  }
}

struct StellarActionsView: View {
  let wallet: BaseWallet

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Stellar Actions")
        .font(.title2)
        .fontWeight(.bold)
        .padding(.horizontal)

      NavigationLink(destination: StellarSignMessageScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "pencil.circle",
          title: "Sign Message"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: StellarSignTransactionScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "signature",
          title: "Sign Transaction"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: StellarSendBalanceScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "paperplane.fill",
          title: "Send Balance"
        )
      }
      .padding(.horizontal)

      NavigationLink(destination: StellarAddTrustlineScreen(wallet: wallet)) {
        WalletActionButton(
          icon: "arrow.right.arrow.left",
          title: "Add Trustline"
        )
      }
      .padding(.horizontal)
    }
    .padding(.vertical)
  }
}

private struct WalletActionButton: View {
  let icon: String
  let title: String

  var body: some View {
    HStack {
      Image(systemName: icon)
      Text(title)
      Spacer()
      Image(systemName: "chevron.right")
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color.blue.opacity(0.1))
    .foregroundColor(.blue)
    .cornerRadius(8)
  }
}

struct DelegationSectionView: View {
  let status: WalletDelegatedStatus
  let isLoading: Bool
  let onEnable: () -> Void
  let onRevoke: () -> Void
    private var statusColor: Color {
    switch status.status {
    case .delegated:
      return .green
    case .denied:
      return .red
    case .pending:
      return .orange
    }
  }
    
 private var statusText: String {
    switch status.status {
    case .delegated:
      return "DELEGATED"
    case .denied:
      return "DENIED"
    case .pending:
      return "PENDING"
    }
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "lock.shield")
          .font(.system(size: 16))
        Text("Delegated Access")
          .font(.headline)
        Spacer()
        Text(statusText)
          .font(.caption)
          .fontWeight(.bold)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(statusColor.opacity(0.2))
          .foregroundColor(statusColor)
          .cornerRadius(4)
      }

      if isLoading {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        .padding(.vertical, 8)
      } else {
        switch status.status {
        case .delegated:
          Button(action: onRevoke) {
            HStack {
              Image(systemName: "minus.circle")
              Text("Revoke Delegated Access")
              Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(8)
          }
        case .pending:
          Button(action: onEnable) {
            HStack {
              Image(systemName: "checkmark.circle")
              Text("Enable Delegated Access")
              Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .foregroundColor(.green)
            .cornerRadius(8)
          }
        case .denied:
          EmptyView()
        }
      }
    }
    .padding()
    .background(Color(.systemBackground).opacity(0.8))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(statusColor.opacity(0.3), lineWidth: 1)
    )
  }
}
