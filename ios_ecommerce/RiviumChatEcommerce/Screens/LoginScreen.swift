import SwiftUI

/// Login screen for selecting demo user.
public struct LoginScreen: View {
    let onLogin: (DemoUser) -> Void

    @State private var selectedUser: DemoUser?

    public init(onLogin: @escaping (DemoUser) -> Void) {
        self.onLogin = onLogin
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo/Header
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("RiviumChat E-commerce")
                .font(.title)
                .fontWeight(.bold)

            Text("Demo Application")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("Select a demo user to continue")
                .font(.headline)

            // User selection cards
            HStack(spacing: 16) {
                UserCard(
                    user: DemoUsers.buyer,
                    isSelected: selectedUser == DemoUsers.buyer,
                    onTap: { selectedUser = DemoUsers.buyer }
                )

                UserCard(
                    user: DemoUsers.seller,
                    isSelected: selectedUser == DemoUsers.seller,
                    onTap: { selectedUser = DemoUsers.seller }
                )
            }
            .padding(.horizontal)

            // Login button
            Button(action: {
                if let user = selectedUser {
                    onLogin(user)
                }
            }) {
                Text("Continue as \(selectedUser?.name ?? "...")")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedUser != nil ? Color.accentColor : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(selectedUser == nil)
            .padding(.horizontal)

            Spacer()

            // Info text
            Text("This demo shows how to integrate RiviumChat SDK into an e-commerce app for buyer-seller communication.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }
}

struct UserCard: View {
    let user: DemoUser
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Avatar
                AsyncImage(url: URL(string: user.avatarUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .overlay(
                            Image(systemName: user.role == .buyer ? "person.fill" : "storefront.fill")
                                .font(.title)
                                .foregroundColor(.accentColor)
                        )
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                Text(user.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Image(systemName: user.role == .buyer ? "person.fill" : "storefront.fill")
                        .font(.caption)
                    Text(user.role.rawValue)
                        .font(.caption)
                }
                .foregroundColor(.accentColor)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color(UIColor.systemBackground)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color(UIColor.separator), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
