import SwiftUI
import Combine
import Supabase

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var nickname = ""
    @Published var quote = ""
    @Published var profileImage: UIImage?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseManager.shared.client
    private var saveCancellable: AnyCancellable?
    private let debounceInterval: TimeInterval = 1.0
    
    init() {
        // Debounce auto-save on field changes
        setupAutoSave()
    }
    
    // MARK: - Setup
    
    private func setupAutoSave() {
        // Combine all text field publishers using nested CombineLatest
        let textFieldsPublisher = Publishers.CombineLatest3(
            $firstName,
            $lastName,
            Publishers.CombineLatest($nickname, $quote)
        )
        .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
        .dropFirst() // Skip initial value
        .sink { [weak self] _, _, _ in
            Task { @MainActor [weak self] in
                await self?.saveProfile()
            }
        }
        
        saveCancellable = textFieldsPublisher
    }
    
    // MARK: - Load Profile
    
    func loadProfile() async {
        guard let user = try? await supabase.auth.session.user else {
            errorMessage = "No user session found"
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let result: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            
            self.profile = result
            self.firstName = result.firstName ?? ""
            self.lastName = result.lastName ?? ""
            self.nickname = result.nickname ?? ""
            self.quote = result.quote ?? ""
            
            // Load profile image if URL exists
            if let imageURL = result.profileImageURL {
                await loadImageFromURL(imageURL)
            }
        } catch {
            // If profile doesn't exist, create one
            if let error = error as? PostgrestError,
               error.code == "PGRST116" { // Not found
                await createProfile(userId: user.id)
            } else {
                errorMessage = "Failed to load profile: \(error.localizedDescription)"
                print("❌ Error loading profile: \(error)")
            }
        }
    }
    
    // MARK: - Create Profile
    
    private func createProfile(userId: UUID) async {
        guard let user = try? await supabase.auth.session.user else { return }
        
        var newProfile: [String: AnyCodable] = [
            "id": AnyCodable(userId.uuidString),
            "email": AnyCodable(user.email ?? "")
        ]
        
        // Add optional fields as nil
        newProfile["first_name"] = AnyCodable(NSNull())
        newProfile["last_name"] = AnyCodable(NSNull())
        newProfile["nickname"] = AnyCodable(NSNull())
        newProfile["quote"] = AnyCodable(NSNull())
        newProfile["profile_image_url"] = AnyCodable(NSNull())
        
        do {
            _ = try await supabase
                .from("profiles")
                .insert(newProfile)
                .execute()
            
            // Reload after creation
            await loadProfile()
        } catch {
            errorMessage = "Failed to create profile: \(error.localizedDescription)"
            print("❌ Error creating profile: \(error)")
        }
    }
    
    // MARK: - Save Profile
    
    func saveProfile() async {
        guard let profile = profile else { return }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        var updates: [String: AnyCodable] = [:]
        updates["first_name"] = firstName.isEmpty ? AnyCodable(NSNull()) : AnyCodable(firstName)
        updates["last_name"] = lastName.isEmpty ? AnyCodable(NSNull()) : AnyCodable(lastName)
        updates["nickname"] = nickname.isEmpty ? AnyCodable(NSNull()) : AnyCodable(nickname)
        updates["quote"] = quote.isEmpty ? AnyCodable(NSNull()) : AnyCodable(quote)
        updates["profile_image_url"] = profile.profileImageURL != nil ? AnyCodable(profile.profileImageURL!) : AnyCodable(NSNull())
        
        do {
            _ = try await supabase
                .from("profiles")
                .update(updates)
                .eq("id", value: profile.id.uuidString)
                .execute()
            
            // Update local profile
            var updatedProfile = profile
            updatedProfile.firstName = firstName.isEmpty ? nil : firstName
            updatedProfile.lastName = lastName.isEmpty ? nil : lastName
            updatedProfile.nickname = nickname.isEmpty ? nil : nickname
            updatedProfile.quote = quote.isEmpty ? nil : quote
            self.profile = updatedProfile
            
            print("✅ Profile saved successfully")
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            print("❌ Error saving profile: \(error)")
        }
    }
    
    // MARK: - Image Upload
    
    func updateProfileImage(_ image: UIImage) {
        self.profileImage = image
        
        Task {
            guard let profile = profile,
                  let imageData = image.jpegData(compressionQuality: 0.8) else {
                errorMessage = "Failed to process image"
                return
            }
            
            let path = "profile_\(profile.id.uuidString).jpg"
            
            do {
                // Upload to Supabase Storage
                _ = try await supabase.storage
                    .from("profile_images")
                    .upload(path: path, file: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))
                
                // Update profile with image path
                var updatedProfile = profile
                updatedProfile.profileImageURL = path
                self.profile = updatedProfile
                
                // Save profile update
                let updates: [String: AnyCodable] = [
                    "profile_image_url": AnyCodable(path)
                ]
                
                _ = try await supabase
                    .from("profiles")
                    .update(updates)
                    .eq("id", value: profile.id.uuidString)
                    .execute()
                
                print("✅ Profile image uploaded successfully")
            } catch {
                errorMessage = "Failed to upload image: \(error.localizedDescription)"
                print("❌ Error uploading image: \(error)")
            }
        }
    }
    
    // MARK: - Load Image from URL
    
    private func loadImageFromURL(_ path: String) async {
        guard !path.isEmpty else { return }
        
        do {
            // Create signed URL (valid for 7 days)
            let signedURL = try await supabase.storage
                .from("profile_images")
                .createSignedURL(path: path, expiresIn: 60 * 60 * 24 * 7)
            
            // Load image data
            let (data, _) = try await URLSession.shared.data(from: signedURL)
            
            await MainActor.run {
                if let image = UIImage(data: data) {
                    self.profileImage = image
                }
            }
        } catch {
            print("⚠️ Could not load profile image: \(error.localizedDescription)")
            // Don't show error for image loading failures
        }
    }
}

