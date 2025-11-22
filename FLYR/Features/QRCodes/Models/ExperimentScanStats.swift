import Foundation

/// Statistics for an A/B test experiment
public struct ExperimentScanStats: Codable, Equatable {
    public let variantA_scans: Int
    public let variantB_scans: Int
    public let variantA_unique: Int
    public let variantB_unique: Int
    public let variantA_conversions: Int
    public let variantB_conversions: Int
    
    public init(
        variantA_scans: Int = 0,
        variantB_scans: Int = 0,
        variantA_unique: Int = 0,
        variantB_unique: Int = 0,
        variantA_conversions: Int = 0,
        variantB_conversions: Int = 0
    ) {
        self.variantA_scans = variantA_scans
        self.variantB_scans = variantB_scans
        self.variantA_unique = variantA_unique
        self.variantB_unique = variantB_unique
        self.variantA_conversions = variantA_conversions
        self.variantB_conversions = variantB_conversions
    }
    
    /// Total scans across both variants
    public var totalScans: Int {
        variantA_scans + variantB_scans
    }
    
    /// Total unique visitors across both variants
    public var totalUnique: Int {
        variantA_unique + variantB_unique
    }
    
    /// Total conversions across both variants
    public var totalConversions: Int {
        variantA_conversions + variantB_conversions
    }
    
    /// Determine winner based on conversions (primary) or scans (fallback)
    public var winner: String? {
        if variantA_conversions > variantB_conversions {
            return "A"
        } else if variantB_conversions > variantA_conversions {
            return "B"
        } else if variantA_scans > variantB_scans {
            return "A"
        } else if variantB_scans > variantA_scans {
            return "B"
        }
        return nil // Tie
    }
    
    /// Conversion rate for variant A
    public var variantA_conversionRate: Double {
        guard variantA_scans > 0 else { return 0.0 }
        return Double(variantA_conversions) / Double(variantA_scans)
    }
    
    /// Conversion rate for variant B
    public var variantB_conversionRate: Double {
        guard variantB_scans > 0 else { return 0.0 }
        return Double(variantB_conversions) / Double(variantB_scans)
    }
}

