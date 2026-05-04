import SwiftUI
import AVKit
import IPTVCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Download Actions and Utilities for AddDownloadView

struct DownloadActions {
    
    static func playAction(movieDetail: MovieDetail, profile: IPTVProfile, onPlayerReady: @escaping (AVPlayer) -> Void) {
        MKSLog.media.info("Acción Play para: \(movieDetail.movieData.name)")
        let urlString = IPTVConfiguration.buildMovieURL(
            profile: profile,
            vodID: String(movieDetail.movieData.streamId),
            vodExtension: movieDetail.movieData.containerExtension ?? "mp4"
        )
        MKSLog.media.debug("URL: \(urlString)")
        
        guard let originalUrl = URL(string: urlString) else {
            MKSLog.media.error("URL inválida: \(urlString)")
            return
        }
        
        let streamManager = StreamManager()
        
        streamManager.resolveStreamURL(from: originalUrl) { resolvedUrl in
            guard let resolvedUrl = resolvedUrl else {
                MKSLog.media.error("No se pudo resolver la URL del stream")
                return
            }
            
            streamManager.setupStreamPlayer(with: resolvedUrl) { player in
                DispatchQueue.main.async {
                    if let player = player {
                        MKSLog.media.info("Player configurado para película")
                        onPlayerReady(player)
                        player.play()
                    } else {
                        MKSLog.media.error("No se pudo configurar el player")
                    }
                }
            }
        }
    }
    
    static func copyURLToClipboard(movieDetail: MovieDetail, profile: IPTVProfile) {
        let urlString = IPTVConfiguration.buildMovieURL(
            profile: profile,
            vodID: String(movieDetail.movieData.streamId),
            vodExtension: movieDetail.movieData.containerExtension ?? "mp4"
        )
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        #else
        UIPasteboard.general.string = urlString
        #endif
        
        MKSLog.media.info("URL copiada al portapapeles")
    }
    
    static func extractYear(from dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            return yearFormatter.string(from: date)
        }
        
        return dateString
    }
    
    static func selectFolder(completion: @escaping (URL?) -> Void) {
        #if os(macOS)
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Seleccionar"
        
        if openPanel.runModal() == .OK {
            completion(openPanel.url)
        } else {
            completion(nil)
        }
        #else
        completion(nil)
        #endif
    }
}

// MARK: - Modal Components

struct DownloadOptionsModal: View {
    @Binding var isModalPresented: Bool
    @Binding var selectedFolder: URL
    @Binding var shouldConvertToMOV: Bool
    let availableFolders: [URL]
    let onDownload: () -> Void
    var metadata: MetadataResult? = nil
    var metadataCandidates: [ScoredMetadataResult] = []
    var onMetadataSelected: ((MetadataResult) -> Void)? = nil

    @State private var showMetadataPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Opciones de descarga")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("Cerrar") {
                    isModalPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondarySystemBackground)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Metadata preview section
                    if let metadata = metadata {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Metadata")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                if !metadataCandidates.isEmpty {
                                    Button("Cambiar") {
                                        showMetadataPicker = true
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            HStack(spacing: 10) {
                                // Poster
                                if let posterURL = metadata.posterURL, let url = URL(string: posterURL) {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 60)
                                                .cornerRadius(4)
                                        } else {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 40, height: 60)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(metadata.title)
                                        .font(.caption.bold())
                                        .lineLimit(1)

                                    HStack(spacing: 6) {
                                        if let year = metadata.year {
                                            Text(String(year))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if !metadata.genre.isEmpty {
                                            Text(metadata.genre.prefix(2).joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if let rating = metadata.rating {
                                            HStack(spacing: 2) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 7))
                                                    .foregroundColor(.yellow)
                                                Text(String(format: "%.1f", rating))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Text("via \(metadata.providerName)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }

                                Spacer()
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }

                    // Selector de carpeta
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Carpeta de destino")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text(selectedFolder.lastPathComponent)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Cambiar") {
                                DownloadActions.selectFolder { url in
                                    if let url = url {
                                        selectedFolder = url
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)

                    // Opción de conversión
                    Toggle("Convertir a MOV", isOn: $shouldConvertToMOV)
                        .padding(.horizontal)

                    Divider()

                    // Carpetas disponibles
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Carpetas rápidas")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(availableFolders, id: \.self) { folder in
                                Button(folder.lastPathComponent) {
                                    selectedFolder = folder
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }

            Divider()

            // Botones de acción
            HStack(spacing: 12) {
                Button("Cancelar") {
                    isModalPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Descargar") {
                    onDownload()
                    isModalPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
        .sheet(isPresented: $showMetadataPicker) {
            if !metadataCandidates.isEmpty {
                let dummyItem = DownloadItem(
                    id: UUID(), vodID: "", title: metadata?.title ?? "",
                    type: .movie, status: .completed,
                    metadataCandidates: metadataCandidates
                )
                MetadataPickerView(
                    downloadItem: dummyItem,
                    onConfirm: { chosen in
                        onMetadataSelected?(chosen)
                        showMetadataPicker = false
                    },
                    onDismiss: { showMetadataPicker = false }
                )
            }
        }
    }
}

// MARK: - Action Buttons View

struct ActionButtonsView: View {
    let movieDetail: MovieDetail
    let profile: IPTVProfile
    let onPlay: () -> Void
    let onDownload: () -> Void
    let onCopyURL: () -> Void
    let onOptions: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Fila principal
            HStack(spacing: 12) {
                // Botón Play
                Button(action: onPlay) {
                    buttonContent(
                        icon: "play.fill",
                        label: "Ver",
                        style: .primary,
                        iconSize: 16,
                        labelSize: 16
                    )
                }
                
                // Botón Descargar
                Button(action: onDownload) {
                    buttonContent(
                        icon: "arrow.down.to.line",
                        label: "Descargar",
                        style: .primary,
                        iconSize: 16,
                        labelSize: 16
                    )
                }
                
                // Botón Copiar URL
                Button(action: onCopyURL) {
                    buttonContent(
                        icon: "link",
                        label: "Copiar URL",
                        style: .secondary,
                        iconSize: 16,
                        labelSize: 16
                    )
                }
            }
            
            // Fila secundaria
            HStack(spacing: 12) {
                // Botón VLC externo
                OpenInVLCButton(urlProvider: {
                    return IPTVConfiguration.buildMovieURL(
                        profile: profile,
                        vodID: String(movieDetail.movieData.streamId),
                        vodExtension: movieDetail.movieData.containerExtension ?? "mp4"
                    )
                }, label: "VLC")
                .controlSize(.small)
                
                // Botón de opciones de descarga
                Button(action: onOptions) {
                    buttonContent(
                        icon: "gearshape.fill",
                        label: "Opciones",
                        style: .secondary,
                        iconSize: 16,
                        labelSize: 16
                    )
                }
                
                // Botón de cancelar
                Button(action: onCancel) {
                    buttonContent(
                        icon: "xmark",
                        label: "Cancelar",
                        style: .cancel,
                        iconSize: 16,
                        labelSize: 16
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private func buttonContent(icon: String, label: String, style: DownloadButtonType, iconSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
            
            Text(label)
                .font(.system(size: labelSize, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(DownloadButtonStyle(type: style))
    }
}
