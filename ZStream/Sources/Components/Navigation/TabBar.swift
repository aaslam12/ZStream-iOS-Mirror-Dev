import SwiftUI

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.icon, value: .home) {
                HomeView()
            }

            Tab(AppTab.downloads.title, systemImage: AppTab.downloads.icon, value: .downloads) {
                DownloadsView()
            }

            Tab(AppTab.profile.title, systemImage: AppTab.profile.icon, value: .profile) {
                ProfileView()
            }

            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
    }
}
