import SwiftUI

/// Component for custom URL input with validation
struct CustomUrlInput: View {
    @Binding var url: String
    @State private var isValid: Bool = true
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom URL")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("https://example.com", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 17))
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .focused($isFocused)
                .onChange(of: url) { _, newValue in
                    validateURL(newValue)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isValid ? Color.clear : Color.red, lineWidth: 1)
                )
            
            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            } else {
                Text("Enter a valid URL (e.g., https://example.com)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func validateURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            isValid = true
            errorMessage = nil
            return
        }
        
        // Basic URL validation
        let urlPattern = #"^https?://[^\s/$.?#].[^\s]*$"#
        let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: urlString.utf16.count)
        
        if let regex = regex, regex.firstMatch(in: urlString, options: [], range: range) != nil {
            // Also check if URL can be created
            if URL(string: urlString) != nil {
                isValid = true
                errorMessage = nil
            } else {
                isValid = false
                errorMessage = "Invalid URL format"
            }
        } else {
            isValid = false
            errorMessage = "URL must start with http:// or https://"
        }
    }
    
    /// Check if the current URL is valid
    var isURLValid: Bool {
        guard !url.isEmpty else { return false }
        return isValid && URL(string: url) != nil
    }
}



