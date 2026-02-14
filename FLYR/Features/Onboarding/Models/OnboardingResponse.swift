import Foundation

struct OnboardingResponse: Codable, Equatable {
    var firstName: String = ""
    var lastName: String = ""
    var profilePhotoURL: String?
    var contactPreference: ContactPreference?
    var industry: Industry?
    var activityType: OnboardingActivityType?
    var territoryType: TerritoryType?
    var experienceLevel: ExperienceLevel?
    var goals: [Goal] = []
    var proExpectations: [ProExpectation] = []
    var proExpectationsOther: String?

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, profilePhotoURL, contactPreference, industry, activityType
        case territoryType, experienceLevel, goals, proExpectations, proExpectationsOther
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        profilePhotoURL = try c.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        contactPreference = try c.decodeIfPresent(ContactPreference.self, forKey: .contactPreference)
        industry = try c.decodeIfPresent(Industry.self, forKey: .industry)
        activityType = try c.decodeIfPresent(OnboardingActivityType.self, forKey: .activityType)
        territoryType = try c.decodeIfPresent(TerritoryType.self, forKey: .territoryType)
        experienceLevel = try c.decodeIfPresent(ExperienceLevel.self, forKey: .experienceLevel)
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        proExpectations = try c.decodeIfPresent([ProExpectation].self, forKey: .proExpectations) ?? []
        proExpectationsOther = try c.decodeIfPresent(String.self, forKey: .proExpectationsOther)
    }

    init() {}

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encodeIfPresent(profilePhotoURL, forKey: .profilePhotoURL)
        try c.encodeIfPresent(contactPreference, forKey: .contactPreference)
        try c.encodeIfPresent(industry, forKey: .industry)
        try c.encodeIfPresent(activityType, forKey: .activityType)
        try c.encodeIfPresent(territoryType, forKey: .territoryType)
        try c.encodeIfPresent(experienceLevel, forKey: .experienceLevel)
        try c.encode(goals, forKey: .goals)
        try c.encode(proExpectations, forKey: .proExpectations)
        try c.encodeIfPresent(proExpectationsOther, forKey: .proExpectationsOther)
    }

    var isComplete: Bool {
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        contactPreference != nil &&
        industry != nil &&
        activityType != nil &&
        territoryType != nil &&
        experienceLevel != nil &&
        !goals.isEmpty
    }

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Contact Preference

enum ContactPreference: String, Codable, CaseIterable {
    case sms = "Text/SMS"
    case email = "Email"
    case pushOnly = "Push notifications only"
    case none = "Don't contact me"

    var icon: String {
        switch self {
        case .sms: return "message.fill"
        case .email: return "envelope.fill"
        case .pushOnly: return "bell.fill"
        case .none: return "bell.slash.fill"
        }
    }

    var description: String {
        switch self {
        case .sms: return "Best for session reminders"
        case .email: return "Weekly summaries"
        case .pushOnly: return "In-app only"
        case .none: return "Just tracking, no nudges"
        }
    }
}

// MARK: - Industry

enum Industry: String, Codable, CaseIterable {
    case realEstate = "Real Estate"
    case politicalCampaign = "Political Campaign"
    case solarHomeServices = "Solar/Home Services"
    case fundraisingNonprofit = "Fundraising/Non-profit"
    case roofing = "Roofing"
    case lawnMaintenance = "Lawn maintenance"
    case other = "Other"
}

// MARK: - Onboarding Activity Type

enum OnboardingActivityType: String, Codable, CaseIterable {
    case doorKnocking = "Door knocking"
    case flyers = "Flyers"
    case both = "Both"
}

// MARK: - Territory Type

enum TerritoryType: String, Codable, CaseIterable {
    case urban = "City"
    case suburban = "Suburban"
    case rural = "Rural"
    case mixed = "Mixed"
}

// MARK: - Experience Level

enum ExperienceLevel: String, Codable, CaseIterable {
    case brandNew = "Brand new"
    case someExperience = "Some experience"
    case veryExperienced = "Very experienced"
    case fullTime = "Full-time"
}

// MARK: - Goal (multi-select motivation)

enum Goal: String, Codable, CaseIterable {
    case stayingConsistent = "Staying consistent"
    case trackingEffort = "Tracking effort"
    case betterResults = "Better results"
    case provingWork = "Proving work"
}

// MARK: - PRO Expectation (multi-select for $30 value question)

enum ProExpectation: String, Codable, CaseIterable {
    case moreInsightsStats = "More insights & stats"
    case territoryPlanning = "Territory planning"
    case proofOfActivity = "Proof of activity"
    case smartFlyerCampaigns = "Smart Flyer campaigns"
    case leadTracking = "Lead tracking"
    case other = "Other"
}
