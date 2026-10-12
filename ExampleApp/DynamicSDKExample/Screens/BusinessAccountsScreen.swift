import SwiftUI
import Combine
import DynamicSDKSwift

// Business Accounts sample screen.
// Mirrors the pattern used by Passkeys/MFA Devices: load a list, expose all
// SDK mutations, and refresh after each change.
struct BusinessAccountsScreen: View {
  @StateObject private var vm = BusinessAccountsViewModel()

  // Create account form
  @State private var createName: String = ""
  @State private var createExternalRef: String = ""
  @State private var createMetadata: String = ""

  // List filter
  @State private var filterExternalRefs: String = ""

  // Rename form
  @State private var renameName: String = ""

  // Add wallet form
  @State private var addWalletId: String = ""

  // Add member form
  @State private var memberUserId: String = ""
  @State private var memberIdentifier: String = ""
  @State private var memberIdentifierType: BusinessAccountSignerIdentifierType?
  @State private var memberRole: BusinessAccountMemberRole = .viewer
  // Add signer form
  @State private var signerWalletId: String = ""
  @State private var signerAccountAddress: String = ""
  @State private var signerChainName: String = ""
  @State private var signerIdentifier: String = ""
  @State private var signerIdentifierType: BusinessAccountSignerIdentifierType?
  @State private var signerUserId: String = ""
  @State private var signerSocialProvider: String = ""
  @State private var signerSmsIso: String = ""
  @State private var signerSmsPhone: String = ""
  @State private var signerPassword: String = ""
  @State private var signerType: BusinessAccountSignerType = .endUser

  // Transfer ownership form
  @State private var transferUserId: String = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if vm.isLoading && vm.accounts == nil {
          HStack { Spacer(); ProgressView(); Spacer() }
            .padding(.top, 40)
        } else if let error = vm.errorMessage {
          ErrorMessageView(message: error)
        }

        createSection()
        filterSection()
        accountPicker()

        if let detail = vm.detail {
          detailContent(detail)
        } else if vm.selectedAccountId != nil && !vm.isLoading {
          Text("Select an account to view details")
            .foregroundColor(.secondary)
        }
      }
      .padding(16)
    }
    .navigationTitle("Business Accounts")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      vm.loadMyWallets()
      Task { await vm.loadAccounts() }
    }
    .refreshable { await vm.loadAccounts() }
    .alert(vm.alertTitle ?? "", isPresented: Binding(
      get: { vm.alertTitle != nil },
      set: { _ in vm.alertTitle = nil; vm.alertMessage = nil }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(vm.alertMessage ?? "")
    }
    .confirmationDialog(vm.confirmTitle, isPresented: $vm.isConfirmPresented, titleVisibility: .visible) {
      Button("Confirm", role: .destructive) {
        Task { await vm.performConfirmedAction() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(vm.confirmMessage)
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private func createSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Create account")
          .font(.headline)
          .fontWeight(.bold)

        TextFieldWithLabel(label: "Name", placeholder: "Account name", text: $createName)
        TextFieldWithLabel(label: "External ref", placeholder: "optional", text: $createExternalRef)
        TextFieldWithLabel(label: "Metadata JSON", placeholder: "{\"key\":\"value\"}", text: $createMetadata)

        PrimaryButton(
          title: "Create",
          action: {
            Task { await vm.createAccount(
              name: createName,
              externalRef: createExternalRef.nilIfEmpty,
              metadata: parseMetadata(createMetadata)
            ) }
          },
          isLoading: vm.isLoading,
          isDisabled: createName.trimmed.isEmpty
        )
      }
    }
  }

  @ViewBuilder
  private func filterSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Filter by external refs")
          .font(.headline)
          .fontWeight(.bold)

        TextFieldWithLabel(
          label: "External refs (comma separated)",
          placeholder: "ref1, ref2",
          text: $filterExternalRefs
        )

        PrimaryButton(
          title: "Apply filter",
          action: {
            Task { await vm.loadAccounts(externalRefs: externalRefs(from: filterExternalRefs)) }
          },
          isLoading: vm.isLoading,
          isDisabled: false
        )
      }
    }
  }

  @ViewBuilder
  private func accountPicker() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Accounts")
          .font(.headline)
          .fontWeight(.bold)

        if let accounts = vm.accounts, !accounts.isEmpty {
          Picker("Select account", selection: $vm.selectedAccountId) {
            ForEach(accounts, id: \.id) { account in
              Text(account.name ?? account.id)
                .tag(Optional(account.id))
            }
          }
          .pickerStyle(.menu)
          .onChange(of: vm.selectedAccountId) { newId in
            if let newId {
              Task { await vm.selectAccount(id: newId) }
            }
          }
        } else {
          Text("No business accounts")
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func detailContent(_ detail: BusinessAccountDetail) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      accountHeader(detail)
      renameSection()
      walletsSection(detail)
      addWalletSection()
      reproLinkWalletSection()
      membersSection(detail)
      addMemberSection()
      signersSection(detail)
      addSignerSection(detail)
      transferSection()
    }
  }

  @ViewBuilder
  private func accountHeader(_ detail: BusinessAccountDetail) -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 8) {
        Text("Account")
          .font(.headline)
          .fontWeight(.bold)

        InfoRow(label: "Name", value: detail.name ?? "N/A")
        InfoRow(label: "ID", value: detail.id)
        InfoRow(label: "External ref", value: detail.externalRef ?? "N/A")
      }
    }
  }

  @ViewBuilder
  private func renameSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Rename account")
          .font(.headline)
          .fontWeight(.bold)

        TextFieldWithLabel(label: "New name", placeholder: "New account name", text: $renameName)

        PrimaryButton(
          title: "Rename",
          action: { Task { await vm.renameAccount(name: renameName) } },
          isLoading: vm.isLoading,
          isDisabled: renameName.trimmed.isEmpty
        )
      }
    }
  }

  @ViewBuilder
  private func walletsSection(_ detail: BusinessAccountDetail) -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Wallets (\(detail.wallets?.count ?? 0))")
          .font(.headline)
          .fontWeight(.bold)

        if let wallets = detail.wallets, !wallets.isEmpty {
          ForEach(wallets, id: \.id) { wallet in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("\(wallet.chain) - \(short(wallet.publicKey))")
                  .font(.subheadline)
                  .fontWeight(.medium)
                Text("ID: \(short(wallet.id))")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }

              Spacer()

              Button("Remove") {
                vm.confirm(
                  title: "Remove wallet",
                  message: "Remove wallet \(short(wallet.id)) from this account?",
                  action: { Task { await vm.removeWallet(walletId: wallet.id) } }
                )
              }
              .buttonStyle(.bordered)
              .tint(.red)
            }
          }
        } else {
          Text("No wallets linked")
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func addWalletSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Link wallet")
          .font(.headline)
          .fontWeight(.bold)

        if !vm.myWallets.isEmpty {
          Picker("My wallets", selection: $addWalletId) {
            Text("Pick one of your wallets").tag("")
            ForEach(vm.myWallets, id: \.id) { wallet in
              if let id = wallet.id {
                Text("\(wallet.chain) - \(short(id))").tag(id)
              }
            }
          }
          .pickerStyle(.menu)
          Text("These come from createWallet (Home screen) — creating a wallet does NOT link it to a business account; linking is the separate step below.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        TextFieldWithLabel(label: "Wallet ID", placeholder: "wallet id to link", text: $addWalletId)

        PrimaryButton(
          title: "Link wallet",
          action: { Task { await vm.addWallet(walletId: addWalletId) } },
          isLoading: vm.isLoading,
          isDisabled: addWalletId.trimmed.isEmpty
        )
      }
    }
  }

  @ViewBuilder
  private func reproLinkWalletSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Repro: client link-wallet hang")
          .font(.headline)
          .fontWeight(.bold)
        Text("Reproduces the reported businessAccounts.addWallet hang using the wallet ID above.")
          .font(.caption)
          .foregroundColor(.secondary)

        if let stepUpRequired = vm.stepUpRequired {
          InfoRow(label: "Step-up required", value: stepUpRequired ? "Yes" : "No")
        }

        HStack {
          PrimaryButton(
            title: "1. Check step-up",
            action: { Task { await vm.checkLinkWalletStepUp() } },
            isLoading: vm.isCheckingStepUp,
            isDisabled: false
          )
          PrimaryButton(
            title: "2. Prompt step-up",
            action: { Task { await vm.promptLinkWalletStepUp() } },
            isLoading: vm.isPromptingStepUp,
            isDisabled: false
          )
        }

        PrimaryButton(
          title: "3. Link wallet (repro)",
          action: { Task { await vm.reproLinkWallet(walletId: addWalletId) } },
          isLoading: vm.isReproRunning,
          isDisabled: addWalletId.trimmed.isEmpty
        )

        if vm.isReproRunning {
          Text("Pending for \(vm.reproElapsedSeconds)s…")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if let status = vm.reproStatus {
          Text(status)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func membersSection(_ detail: BusinessAccountDetail) -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Members (\(detail.members.count))")
          .font(.headline)
          .fontWeight(.bold)

        if !detail.members.isEmpty {
          ForEach(detail.members, id: \.id) { member in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text("User: \(member.userId)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                  Text("Role: \(member.role.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                  Button("Make admin") {
                    Task { await vm.updateMemberRole(userId: member.userId, role: .admin) }
                  }
                  Button("Make viewer") {
                    Task { await vm.updateMemberRole(userId: member.userId, role: .viewer) }
                  }
                  Button("Transfer ownership") {
                    vm.confirm(
                      title: "Transfer ownership",
                      message: "Transfer ownership to \(member.userId)?",
                      action: { Task { await vm.transferOwnership(newOwnerUserId: member.userId) } }
                    )
                  }
                  Button("Remove", role: .destructive) {
                    vm.confirm(
                      title: "Remove member",
                      message: "Remove member \(member.userId)?",
                      action: { Task { await vm.removeMember(userId: member.userId) } }
                    )
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                    .foregroundColor(.blue)
                }
              }
            }
          }
        } else {
          Text("No members")
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func addMemberSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Add member")
          .font(.headline)
          .fontWeight(.bold)

        TextFieldWithLabel(label: "User ID", placeholder: "optional", text: $memberUserId)
        TextFieldWithLabel(label: "Identifier", placeholder: "email, phone, etc.", text: $memberIdentifier)
        identifierTypePicker(selection: $memberIdentifierType, label: "Identifier type")
        rolePicker(selection: $memberRole)

        PrimaryButton(
          title: "Add member",
          action: {
            Task { await vm.addMember(
              userId: memberUserId.nilIfEmpty,
              identifier: memberIdentifier.nilIfEmpty,
              identifierType: effectiveIdentifierType(for: memberIdentifier, selected: memberIdentifierType),
              role: memberRole
            ) }
          },
          isLoading: vm.isLoading,
          isDisabled: !canAddMember
        )
      }
    }
  }

  @ViewBuilder
  private func signersSection(_ detail: BusinessAccountDetail) -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Signers (\(detail.signers.count))")
          .font(.headline)
          .fontWeight(.bold)

        if !detail.signers.isEmpty {
          ForEach(detail.signers, id: \.id) { signer in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("Type: \(signer.type)")
                  .font(.subheadline)
                  .fontWeight(.medium)
                Text("Wallet: \(short(signer.walletId))")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }

              Spacer()

              Button("Remove") {
                vm.confirm(
                  title: "Remove signer",
                  message: "Remove signer from wallet \(short(signer.walletId))?",
                  action: { Task { await vm.removeSigner(walletId: signer.walletId, signerId: signer.id) } }
                )
              }
              .buttonStyle(.bordered)
              .tint(.red)
            }
          }
        } else {
          Text("No signers")
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func addSignerSection(_ detail: BusinessAccountDetail) -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Add signer")
          .font(.headline)
          .fontWeight(.bold)

        if let wallets = detail.wallets, !wallets.isEmpty {
          Picker("Target wallet", selection: $signerWalletId) {
            ForEach(wallets, id: \.id) { wallet in
              Text("\(wallet.chain) - \(short(wallet.publicKey))")
                .tag(wallet.id)
            }
          }
          .pickerStyle(.menu)
          .onChange(of: signerWalletId) { newId in
            if let wallet = detail.wallets?.first(where: { $0.id == newId }) {
              signerAccountAddress = wallet.publicKey
              signerChainName = wallet.chain
            }
          }
        }

        TextFieldWithLabel(label: "Account address", placeholder: "0x...", text: $signerAccountAddress)
        TextFieldWithLabel(label: "Chain name", placeholder: "EVM", text: $signerChainName)
        TextFieldWithLabel(label: "Wallet ID", placeholder: "business wallet id", text: $signerWalletId)

        TextFieldWithLabel(label: "Identifier", placeholder: "email, phone, etc.", text: $signerIdentifier)
        identifierTypePicker(selection: $signerIdentifierType, label: "Identifier type")
        TextFieldWithLabel(label: "User ID", placeholder: "optional", text: $signerUserId)

        if signerIdentifierType == .phoneNumber {
          TextFieldWithLabel(label: "SMS ISO code", placeholder: "US", text: $signerSmsIso)
          TextFieldWithLabel(label: "SMS phone code", placeholder: "1", text: $signerSmsPhone)
        }

        if signerIdentifierType == .socialUsername || signerIdentifierType == .socialAccountId {
          TextFieldWithLabel(label: "Social provider", placeholder: "google", text: $signerSocialProvider)
        }

        TextFieldWithLabel(label: "Password", placeholder: "optional", text: $signerPassword)
        signerTypePicker(selection: $signerType)

        PrimaryButton(
          title: "Add signer",
          action: {
            let target = buildTargetIdentity(
              identifier: signerIdentifier,
              identifierType: effectiveIdentifierType(for: signerIdentifier, selected: signerIdentifierType),
              userId: signerUserId,
              socialProvider: signerSocialProvider,
              smsIso: signerSmsIso,
              smsPhone: signerSmsPhone
            )
            Task { await vm.addSigner(
              accountAddress: signerAccountAddress,
              chainName: signerChainName,
              walletId: signerWalletId,
              target: target,
              signerType: signerType,
              password: signerPassword.nilIfEmpty
            ) }
          },
          isLoading: vm.isLoading,
          isDisabled: !canAddSigner
        )
      }
    }
  }

  @ViewBuilder
  private func transferSection() -> some View {
    CardContainer {
      VStack(alignment: .leading, spacing: 12) {
        Text("Transfer ownership")
          .font(.headline)
          .fontWeight(.bold)

        TextFieldWithLabel(label: "New owner user ID", placeholder: "user id", text: $transferUserId)

        PrimaryButton(
          title: "Transfer ownership",
          action: {
            vm.confirm(
              title: "Transfer ownership",
              message: "Transfer ownership to \(transferUserId)?",
              action: { Task { await vm.transferOwnership(newOwnerUserId: transferUserId) } }
            )
          },
          isLoading: vm.isLoading,
          isDisabled: transferUserId.trimmed.isEmpty
        )
      }
    }
  }

  // MARK: - Pickers

  @ViewBuilder
  private func identifierTypePicker(
    selection: Binding<BusinessAccountSignerIdentifierType?>,
    label: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.subheadline)
        .fontWeight(.medium)

      Picker(label, selection: selection) {
        Text("Use user ID only").tag(nil as BusinessAccountSignerIdentifierType?)
        ForEach(BusinessAccountSignerIdentifierType.allCases, id: \.rawValue) { type in
          Text(type.rawValue).tag(Optional(type))
        }
      }
      .pickerStyle(.menu)
    }
  }

  @ViewBuilder
  private func rolePicker(selection: Binding<BusinessAccountMemberRole>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Role")
        .font(.subheadline)
        .fontWeight(.medium)

      Picker("Role", selection: selection) {
        ForEach(BusinessAccountMemberRole.allCases, id: \.rawValue) { role in
          Text(role.rawValue).tag(role)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  @ViewBuilder
  private func signerTypePicker(selection: Binding<BusinessAccountSignerType>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Signer type")
        .font(.subheadline)
        .fontWeight(.medium)

      Picker("Signer type", selection: selection) {
        ForEach(BusinessAccountSignerType.allCases, id: \.rawValue) { type in
          Text(type.rawValue).tag(type)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  // MARK: - Helpers

  private var canAddMember: Bool {
    !vm.isLoading && (!memberUserId.trimmed.isEmpty || !memberIdentifier.trimmed.isEmpty)
  }

  private var canAddSigner: Bool {
    !vm.isLoading &&
    !signerAccountAddress.trimmed.isEmpty &&
    !signerChainName.trimmed.isEmpty &&
    !signerWalletId.trimmed.isEmpty &&
    (!signerIdentifier.trimmed.isEmpty || !signerUserId.trimmed.isEmpty)
  }

  private func parseMetadata(_ value: String) -> [String: Any]? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }

    guard let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
      return nil
    }
    return dict
  }

  private func externalRefs(from value: String) -> [String]? {
    let parts = value
      .components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts
  }

  private func effectiveIdentifierType(
    for identifier: String,
    selected: BusinessAccountSignerIdentifierType?
  ) -> BusinessAccountSignerIdentifierType? {
    if identifier.trimmed.isEmpty { return nil }
    return selected ?? .email
  }

  private func buildTargetIdentity(
    identifier: String,
    identifierType: BusinessAccountSignerIdentifierType?,
    userId: String,
    socialProvider: String,
    smsIso: String,
    smsPhone: String
  ) -> TargetIdentity {
    let smsCountryCode: SmsCountryCode?
    if identifierType == .phoneNumber && !smsIso.isEmpty && !smsPhone.isEmpty {
      smsCountryCode = SmsCountryCode(isoCountryCode: smsIso, phoneCountryCode: smsPhone)
    } else {
      smsCountryCode = nil
    }

    let provider: String? = socialProvider.nilIfEmpty

    return TargetIdentity(
      identifier: identifier.nilIfEmpty,
      identifierType: identifierType,
      smsCountryCode: smsCountryCode,
      socialProvider: provider,
      userId: userId.nilIfEmpty
    )
  }

  private func short(_ value: String) -> String {
    if value.count > 20 {
      return "\(value.prefix(6))...\(value.suffix(4))"
    }
    return value
  }
}

// MARK: - ViewModel

@MainActor
final class BusinessAccountsViewModel: ObservableObject {
  @Published var accounts: [BusinessAccount]?
  @Published var selectedAccountId: String?
  @Published var detail: BusinessAccountDetail?
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?

  @Published var alertTitle: String?
  @Published var alertMessage: String?

  @Published var isConfirmPresented: Bool = false
  @Published var confirmTitle: String = ""
  @Published var confirmMessage: String = ""
  private var pendingConfirmAction: (() async -> Void)?

  // Repro: client link-wallet hang
  @Published var myWallets: [BaseWallet] = []
  @Published var stepUpRequired: Bool?
  @Published var isCheckingStepUp: Bool = false
  @Published var isPromptingStepUp: Bool = false
  @Published var isReproRunning: Bool = false
  @Published var reproElapsedSeconds: Int = 0
  @Published var reproStatus: String?
  private var cancellables = Set<AnyCancellable>()
  private var isSubscribedToWalletChanges = false

  private let sdk = DynamicSDK.instance()

  func loadAccounts(externalRefs: [String]? = nil) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      let list = try await sdk.businessAccounts.list(externalRefs: externalRefs)
      accounts = list.items
      if let first = accounts?.first {
        selectedAccountId = first.id
      } else {
        selectedAccountId = nil
        detail = nil
      }
    } catch {
      errorMessage = "Failed to load business accounts: \(error)"
    }
  }

  func selectAccount(id: String) async {
    selectedAccountId = id
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      detail = try await sdk.businessAccounts.get(businessAccountId: id)
    } catch {
      errorMessage = "Failed to load account details: \(error)"
      detail = nil
    }
  }

  func createAccount(name: String, externalRef: String? = nil, metadata: [String: Any]? = nil) async {
    isLoading = true
    defer { isLoading = false }

    do {
      let account = try await sdk.businessAccounts.create(
        name: name,
        externalRef: externalRef,
        metadata: metadata
      )
      showSuccess("Business account created")
      await loadAccounts()
      let accountId = account.id
      selectedAccountId = accountId
      await selectAccount(id: accountId)
    } catch {
      showError("Failed to create business account: \(error)")
    }
  }

  func renameAccount(name: String) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      _ = try await sdk.businessAccounts.update(businessAccountId: id, name: name)
      showSuccess("Business account renamed")
      await loadAccounts()
      await selectAccount(id: id)
    } catch {
      showError("Failed to rename business account: \(error)")
    }
  }

  func addWallet(walletId: String) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      detail = try await sdk.businessAccounts.addWallet(businessAccountId: id, walletId: walletId)
      showSuccess("Wallet linked")
    } catch {
      showError("Failed to link wallet: \(error)")
    }
  }

  func removeWallet(walletId: String) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      detail = try await sdk.businessAccounts.removeWallet(businessAccountId: id, walletId: walletId)
      showSuccess("Wallet removed")
    } catch {
      showError("Failed to remove wallet: \(error)")
    }
  }

  /// Loads the caller's own embedded wallets (from `createWallet`, e.g. on the
  /// Home screen) so a real walletId is available to link — these are a
  /// separate list from the business account's own `wallets`.
  func loadMyWallets() {
    myWallets = sdk.wallets.userWallets
    guard !isSubscribedToWalletChanges else { return }
    isSubscribedToWalletChanges = true
    sdk.wallets.userWalletsChanges
      .receive(on: DispatchQueue.main)
      .sink { [weak self] wallets in
        self?.myWallets = wallets
      }
      .store(in: &cancellables)
  }

  func checkLinkWalletStepUp() async {
    isCheckingStepUp = true
    defer { isCheckingStepUp = false }

    do {
      stepUpRequired = try await sdk.stepUpAuth.isStepUpRequired(scope: .businessAccountLinkWallet)
    } catch {
      showError("Failed to check step-up: \(error)")
    }
  }

  func promptLinkWalletStepUp() async {
    isPromptingStepUp = true
    defer { isPromptingStepUp = false }

    do {
      _ = try await sdk.stepUpAuth.promptStepUpAuth(requestedScopes: [.businessAccountLinkWallet])
      await checkLinkWalletStepUp()
    } catch {
      showError("Failed to prompt step-up: \(error)")
    }
  }

  /// Calls the real `businessAccounts.addWallet` (no mocks) and reports elapsed
  /// time while it's pending. The request is bounded by `RequestChannel`'s 30s
  /// timeout, so if the webview never sends a resolve/reject the call rejects
  /// with `DynamicSDKError.timeout` instead of hanging forever.
  func reproLinkWallet(walletId: String) async {
    guard let id = selectedAccountId else { return }
    isReproRunning = true
    reproElapsedSeconds = 0
    reproStatus = "Pending…"

    let watchdog = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        self.reproElapsedSeconds += 1
        if self.reproElapsedSeconds == 15 {
          self.reproStatus = "⏳ still pending after 15s with no resolve/reject — reproduces the reported hang"
        }
      }
    }

    do {
      let result = try await sdk.businessAccounts.addWallet(businessAccountId: id, walletId: walletId)
      watchdog.cancel()
      detail = result
      reproStatus = "✅ resolved after \(reproElapsedSeconds)s"
    } catch {
      watchdog.cancel()
      reproStatus = "❌ rejected after \(reproElapsedSeconds)s: \(error)"
    }
    isReproRunning = false
  }

  func addMember(
    userId: String? = nil,
    identifier: String? = nil,
    identifierType: BusinessAccountSignerIdentifierType? = nil,
    role: BusinessAccountMemberRole? = nil
  ) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      _ = try await sdk.businessAccounts.addMember(
        businessAccountId: id,
        userId: userId,
        identifier: identifier,
        identifierType: identifierType,
        role: role
      )
      showSuccess("Member added")
      await refreshDetail()
    } catch {
      showError("Failed to add member: \(error)")
    }
  }

  func removeMember(userId: String) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      _ = try await sdk.businessAccounts.removeMember(businessAccountId: id, userId: userId)
      showSuccess("Member removed")
      await refreshDetail()
    } catch {
      showError("Failed to remove member: \(error)")
    }
  }

  func updateMemberRole(userId: String, role: BusinessAccountMemberRole) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      _ = try await sdk.businessAccounts.updateMemberRole(
        businessAccountId: id,
        userId: userId,
        role: role
      )
      showSuccess("Member role updated")
      await refreshDetail()
    } catch {
      showError("Failed to update member role: \(error)")
    }
  }

  func transferOwnership(newOwnerUserId: String) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      detail = try await sdk.businessAccounts.transferOwnership(
        businessAccountId: id,
        newOwnerUserId: newOwnerUserId
      )
      showSuccess("Ownership transferred")
      await refreshDetail()
    } catch {
      showError("Failed to transfer ownership: \(error)")
    }
  }

  func addSigner(
    accountAddress: String,
    chainName: String,
    walletId: String,
    target: TargetIdentity,
    signerType: BusinessAccountSignerType? = nil,
    password: String? = nil
  ) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      _ = try await sdk.businessAccounts.addSigner(
        accountAddress: accountAddress,
        chainName: chainName,
        targetSignerIdentity: target,
        businessAccountId: id,
        walletId: walletId,
        signerType: signerType,
        password: password
      )
      showSuccess("Signer added")
      await refreshDetail()
    } catch {
      showError("Failed to add signer: \(error)")
    }
  }

  func removeSigner(walletId: String, signerId: String) async {
    guard let id = selectedAccountId else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      _ = try await sdk.businessAccounts.removeSigner(
        businessAccountId: id,
        walletId: walletId,
        signerId: signerId
      )
      showSuccess("Signer removed")
      await refreshDetail()
    } catch {
      showError("Failed to remove signer: \(error)")
    }
  }

  func confirm(title: String, message: String, action: @escaping () async -> Void) {
    confirmTitle = title
    confirmMessage = message
    pendingConfirmAction = action
    isConfirmPresented = true
  }

  func performConfirmedAction() async {
    isConfirmPresented = false
    guard let action = pendingConfirmAction else { return }
    pendingConfirmAction = nil
    await action()
  }

  private func refreshDetail() async {
    guard let id = selectedAccountId else { return }
    await selectAccount(id: id)
  }

  private func showSuccess(_ message: String) {
    alertTitle = "Success"
    alertMessage = message
  }

  private func showError(_ message: String) {
    alertTitle = "Error"
    alertMessage = message
  }
}

// MARK: - String helpers

private extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nilIfEmpty: String? {
    let trimmed = self.trimmed
    return trimmed.isEmpty ? nil : trimmed
  }
}
