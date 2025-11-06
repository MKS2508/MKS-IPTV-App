//
//  PlatformNavigationView.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 22/3/25.
//


import SwiftUI

struct PlatformNavigationView<SidebarContent: View, DetailContent: View>: View {
    @ViewBuilder let sidebarContent: () -> SidebarContent
    @ViewBuilder let detailContent: () -> DetailContent
    @Binding var selectedItem: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        #if os(macOS)
        macOSNavigationView
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Use split view on iPad
            iPadNavigationView
        } else {
            // Use tab bar on iPhone
            iPhoneNavigationView
        }
        #endif
    }
    
    private var macOSNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent()
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                .listStyle(SidebarListStyle())
        } detail: {
            detailContent()
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    private var iPadNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent()
                .listStyle(SidebarListStyle())
        } detail: {
            detailContent()
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    private var iPhoneNavigationView: some View {
        TabView(selection: $selectedItem) {
            NavigationStack {
                detailContent()
            }
            .tabItem {
                Label("Movies", systemImage: "film")
            }
            .tag("Movies")
            
            NavigationStack {
                detailContent()
            }
            .tabItem {
                Label("Series", systemImage: "video")
            }
            .tag("Series")
            
            NavigationStack {
                detailContent()
            }
            .tabItem {
                Label("Live TV", systemImage: "tv")
            }
            .tag("LiveChannels")
            
            NavigationStack {
                detailContent()
            }
            .tabItem {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .tag("Downloads")
        }
    }
}

// Extension to help with platform detection in SwiftUI previews
#if canImport(UIKit)
import UIKit
extension UIDevice {
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}
#endif

// MARK: - Preview
struct PlatformNavigationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // macOS Preview
            #if os(macOS)
            PreviewContainer()
                .frame(width: 1200, height: 800)
                .previewDisplayName("macOS - Split View")
            #endif
            
            // iPad Preview
            #if os(iOS)
            PreviewContainer()
                .previewDevice("iPad Pro (12.9-inch) (6th generation)")
                .previewDisplayName("iPad - Split View")
            
            // iPhone Preview
            PreviewContainer()
                .previewDevice("iPhone 14 Pro")
                .previewDisplayName("iPhone - Tab Bar")
            #endif
        }
    }
    
    struct PreviewContainer: View {
        @State private var selectedItem: String? = "Movies"
        
        var body: some View {
            PlatformNavigationView(
                sidebarContent: {
                    List(selection: $selectedItem) {
                        NavigationLink(value: "Movies") {
                            Label("Movies", systemImage: "film")
                        }
                        
                        NavigationLink(value: "Series") {
                            Label("Series", systemImage: "tv")
                        }
                        
                        NavigationLink(value: "LiveChannels") {
                            Label("Live TV", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        
                        NavigationLink(value: "Downloads") {
                            Label("Downloads", systemImage: "arrow.down.circle")
                        }
                    }
                },
                detailContent: {
                    VStack {
                        if let selectedItem = selectedItem {
                            Text(selectedItem)
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            
                            Text("Content for \(selectedItem) would appear here")
                                .font(.title2)
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding()
                        } else {
                            Text("Select an item from the sidebar")
                                .font(.title)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.05))
                },
                selectedItem: $selectedItem
            )
        }
    }
}
