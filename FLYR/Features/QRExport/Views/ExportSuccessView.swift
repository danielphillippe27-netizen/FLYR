import SwiftUI
import UIKit

/// Success view showing export results with URLs and share options
struct ExportSuccessView: View {
    let exportResult: ExportResult
    let onDone: () -> Void
    
    @State private var copiedURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success indicator
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    
                    Text("Export Complete")
                        .font(.system(size: 24, weight: .bold))
                    
                    Text("\(exportResult.addressCount) QR codes exported")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)
                
                // File URLs
                VStack(alignment: .leading, spacing: 16) {
                    Text("Generated Files")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if let pdfGridURL = exportResult.pdfGridURL {
                        FileURLRow(
                            title: "PDF Grid",
                            url: pdfGridURL,
                            copiedURL: $copiedURL
                        )
                    }
                    
                    if let pdfSingleURL = exportResult.pdfSingleURL {
                        FileURLRow(
                            title: "PDF Single",
                            url: pdfSingleURL,
                            copiedURL: $copiedURL
                        )
                    }
                    
                    if let zipURL = exportResult.zipURL {
                        FileURLRow(
                            title: "ZIP Archive",
                            url: zipURL,
                            copiedURL: $copiedURL
                        )
                    }
                    
                    if let csvURL = exportResult.csvURL {
                        FileURLRow(
                            title: "CSV File",
                            url: csvURL,
                            copiedURL: $copiedURL
                        )
                    }
                    
                    if let pngDirectoryURL = exportResult.pngDirectoryURL {
                        FileURLRow(
                            title: "PNG Directory",
                            url: pngDirectoryURL,
                            copiedURL: $copiedURL
                        )
                    }
                }
                .padding(.horizontal)
                
                // Action buttons
                VStack(spacing: 12) {
                    // Share button
                    Button {
                        shareExport()
                    } label: {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    // Done button
                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
    
    /// Share export files
    private func shareExport() {
        var items: [URL] = []
        
        if let pdfGridURL = exportResult.pdfGridURL {
            items.append(pdfGridURL)
        }
        if let pdfSingleURL = exportResult.pdfSingleURL {
            items.append(pdfSingleURL)
        }
        if let zipURL = exportResult.zipURL {
            items.append(zipURL)
        }
        if let csvURL = exportResult.csvURL {
            items.append(csvURL)
        }
        
        guard !items.isEmpty else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            
            // Configure for iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(
                    x: rootViewController.view.bounds.midX,
                    y: rootViewController.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(activityVC, animated: true)
        }
    }
}

/// Row displaying a file URL with copy functionality
private struct FileURLRow: View {
    let title: String
    let url: URL
    @Binding var copiedURL: URL?
    
    @State private var showCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                
                Spacer()
                
                Button {
                    copyURL()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                        Text(showCopied ? "Copied" : "Copy")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(showCopied ? .green : .blue)
                }
            }
            
            // URL display
            if url.isFileURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(url.absoluteString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func copyURL() {
        let pasteboard = UIPasteboard.general
        if url.isFileURL {
            pasteboard.string = url.lastPathComponent
        } else {
            pasteboard.string = url.absoluteString
        }
        
        copiedURL = url
        showCopied = true
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedURL == url {
                showCopied = false
                copiedURL = nil
            }
        }
    }
}

