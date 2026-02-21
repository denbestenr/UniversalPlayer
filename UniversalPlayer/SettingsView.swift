import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    var onOpenLocalFiles: (() -> Void)?
    var onOpenNetworkBrowser: (() -> Void)?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Bestanden openen")) {
                    Button(action: {
                        onOpenLocalFiles?()
                    }) {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Lokale bestanden")
                                .foregroundColor(.primary)
                        }
                    }

                    Button(action: {
                        onOpenNetworkBrowser?()
                    }) {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(.orange)
                                .frame(width: 30)
                            Text("Netwerkserver (SMB)")
                                .foregroundColor(.primary)
                        }
                    }
                }

                Section(header: Text("Accounts")) {
                    NavigationLink(destination: YouTubeSettingsView()) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundColor(.red)
                                .frame(width: 30)
                            Text("YouTube")
                        }
                    }
                }

                Section(header: Text("Over")) {
                    HStack {
                        Text("Versie")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Instellingen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
