import Foundation
@_spi(Experimental) import MapboxMaps
import UIKit
import CoreLocation

// MARK: - Status Colors

/// Shared campaign status palette. Mirrors the web map status config.
enum MapStatusColor {
    static let untouchedLight = UIColor(hex: "#cfd8e3")!  // Light blue-grey (unvisited on light maps)
    static let untouchedDark = UIColor(hex: "#475569")!   // Dark Slate (unvisited on dark maps)
    static var useLightMapBuildingDefault = false
    static var untouched: UIColor {
        useLightMapBuildingDefault ? untouchedLight : untouchedDark
    }
    static let flyerUntouched = UIColor(hex: "#ef4444")!  // Red (flyer unvisited)
    static let touched = UIColor(hex: "#22c55e")!         // Green (visited)
    static let conversations = UIColor(hex: "#22c55e")!   // Green (talked)
    static let lead = UIColor(hex: "#2563eb")!            // Blue (lead)
    static let hotLead = UIColor(hex: "#facc15")!         // Gold (appointment / follow-up)
    static let qrScanned = UIColor(hex: "#8b5cf6")!       // Purple (QR scan)
    static let noOneHome = UIColor(hex: "#f87171")!       // Coral / muted red
    static let doNotKnock = UIColor(hex: "#000000")!      // Black
    static let pendingVisited = UIColor(hex: "#f59e0b")!  // Amber
    static let teammateTouched = UIColor(hex: "#166534")! // Dark green
    static let orphan = UIColor(hex: "#9ca3af")!          // Gray

    static let roadPrimary = UIColor(hex: "#64748b")!     // Slate
    static let roadSecondary = UIColor(hex: "#94a3b8")!   // Light Slate
    static let addressMarker = UIColor(hex: "#8b5cf6")!   // Purple
    static let selectedHome = UIColor(hex: "#94a3b8")!    // Light Slate
    static let selectedHomeGlow = UIColor(hex: "#cbd5e1")!
}

// MARK: - Map Layer Manager

/// Manages Mapbox layers for buildings, addresses, and roads
/// Mirrors FLYR-PRO's MapBuildingsLayer.tsx functionality
@MainActor
final class MapLayerManager {
    
    // MARK: - Layer IDs
    
    static let buildingsSourceId = "buildings-source"
    static let buildingsLayerId = "buildings-extrusion"
    static let buildingsLeadGlowLayerId = "buildings-lead-glow"
    static let buildingsSelectedGlowLayerId = "buildings-selected-glow"
    static let townhomeOverlaySourceId = "townhome-status-source"
    static let townhomeOverlayLayerId = "townhome-status-extrusion"
    static let townhomeOutlineLayerId = "townhome-status-outlines"
    static let townhomeSliceOutlineLayerId = "townhome-status-slice-outlines"
    static let townhomeDividerLayerId = "townhome-status-dividers"
    static let townhomeDividerStripLayerId = "townhome-status-divider-strips"
    static let townhomeLeadGlowLayerId = "townhome-status-lead-glow"
    
    /// Web-aligned IDs (campaign-address-points, campaign-address-points-extrusion)
    static let addressesSourceId = "campaign-address-points"
    static let addressesLayerId = "campaign-address-points-extrusion"
    static let selectedAddressesLayerId = "campaign-address-points-selected-extrusion"
    static let addressesLeadGlowLayerId = "campaign-address-points-lead-glow"
    static let addressNumbersSourceId = "campaign-address-numbers"
    static let addressHouseIconLayerId = "campaign-address-house-icons-layer"
    static let addressNumbersLayerId = "campaign-address-numbers-layer"
    static let addressLabelHitboxLayerId = "campaign-address-label-hitboxes-layer"
    static let manualAddressPreviewSourceId = "manual-address-preview-source"
    static let manualAddressPreviewLayerId = "manual-address-preview-extrusion"
    static let teammatePresenceSourceId = "campaign-teammate-presence-source"
    static let teammatePresenceCircleLayerId = "campaign-teammate-presence-circles"
    static let teammatePresenceLabelLayerId = "campaign-teammate-presence-labels"
    
    static let roadsSourceId = "roads-source"
    static let roadsLayerId = "roads-line"

    static let parcelsSourceId = "campaign-parcels-source"
    static let parcelsFillLayerId = "campaign-parcels-fill"
    static let parcelsLineLayerId = "campaign-parcels-line"
    static let parcelsOverviewMinZoom: Double = 13.5
    static let parcelsOverviewMaxZoom: Double = 24.0
    private static let addressModeMinimumZoom: Double = 0.0
    private static let addressModeMaximumZoom: Double = 24.0
    
    // MARK: - Address markers zoom (3D cylinders + house number labels)
    
    /// Shared layer min zoom for 3D address markers.
    private static let addressMarkersLayerMinZoom: Double = 11.8
    /// House numbers are only readable at close range; keep them out of overview zooms.
    private static let addressNumbersLayerMinZoom: Double = 17.0
    private static let addressHouseIconImageId = "campaign-address-house-emblem"

    static let defaultBuildingExtrusionHeight: Double = 8.0
    static let maximumBuildingExtrusionHeight: Double = 14.0
    private static let selectedBuildingHeightScale: Double = 1.0
    private static let townhomeOverlayHeightLift: Double = 0.08
    private static let townhomeOverlayPlateThickness: Double = 0.045
    private static let townhomeDividerLineLift: Double = 0.04
    private static let townhomeOverlayMinimumUnitCount = 2
    private static let addressMarkerExtrusionHeight: Double = 5.5
    private static let addressNumberRoofClearance: Double = 1.35
    private static let interactionBuildingExtrusionHeight: Double = 1.25
    private static let interactionAddressExtrusionHeight: Double = 1.0

    private static var addressMarkerExtrusionHeightExpression: Exp {
        Exp(.max) {
            Exp(.toNumber) {
                Exp(.coalesce) {
                    Exp(.featureState) { "height_m" }
                    Exp(.get) { "height_m" }
                    Exp(.featureState) { "height" }
                    Exp(.get) { "height" }
                    Self.addressMarkerExtrusionHeight
                }
            }
            Self.addressMarkerExtrusionHeight
        }
    }

    private static var addressMarkerExtrusionBaseExpression: Exp {
        Exp(.max) {
            Exp(.toNumber) {
                Exp(.coalesce) {
                    Exp(.featureState) { "min_height" }
                    Exp(.get) { "min_height" }
                    0
                }
            }
            0
        }
    }

    static var buildingExtrusionHeightExpression: Exp {
        Exp(.min) {
            Exp(.max) {
                Exp(.toNumber) {
                    Exp(.coalesce) {
                        Exp(.get) { "render_height" }
                        Exp(.get) { "height_m" }
                        Exp(.get) { "height" }
                        Exp(.get) { "min_height" }
                        Self.defaultBuildingExtrusionHeight
                    }
                }
                Self.defaultBuildingExtrusionHeight
            }
            Self.maximumBuildingExtrusionHeight
        }
    }

    static var buildingExtrusionMinHeightExpression: Exp {
        Exp(.max) {
            Exp(.toNumber) {
                Exp(.coalesce) {
                    Exp(.get) { "min_height" }
                    0.0
                }
            }
            0.0
        }
    }

    static var buildingExtrusionBaseExpression: Exp {
        Exp(.switchCase) {
            Exp(.lt) {
                Self.buildingExtrusionMinHeightExpression
                Self.buildingExtrusionHeightExpression
            }
            Self.buildingExtrusionMinHeightExpression
            0.0
        }
    }

    private static var isSelectedExpression: Exp {
        Exp(.eq) {
            Exp(.coalesce) {
                Exp(.featureState) { "selected" }
                false
            }
            true
        }
    }

    private static var layerStatusExpression: Exp {
        Exp(.coalesce) {
            Exp(.featureState) { "status" }
            Exp(.get) { "status" }
            Exp(.get) { "address_status" }
            Exp(.get) { "building_status" }
            Exp(.get) { "home_status" }
            "not_visited"
        }
    }

    private static var scansTotalExpression: Exp {
        Exp(.coalesce) {
            Exp(.featureState) { "scans_total" }
            Exp(.get) { "scans_total" }
            0
        }
    }

    private static var isSelectedUnvisitedExpression: Exp {
        Exp(.all) {
            Self.isSelectedExpression
            Exp(.lte) {
                Self.scansTotalExpression
                0
            }
            Exp(.match) {
                Self.layerStatusExpression
                ["none", "not_visited", "unvisited", "flyer_unvisited"]
                true
                false
            }
        }
    }

    private static var isActiveStatusExpression: Exp {
        Exp(.match) {
            Self.layerStatusExpression
            ["visited", "delivered", "talked", "hot", "conversation", "lead", "future_seller", "hot_lead", "appointment", "follow_up", "no_answer", "do_not_knock", "not_interested", "flyer_unvisited"]
            true
            false
        }
    }

    private static var isSelectedUnvisitedSegmentExpression: Exp {
        Exp(.all) {
            Self.isSelectedExpression
            Exp(.match) {
                Exp(.coalesce) {
                    Exp(.get) { "segment_status" }
                    "not_visited"
                }
                ["none", "not_visited", "unvisited", "flyer_unvisited"]
                true
                false
            }
        }
    }

    static var selectedBuildingExtrusionHeightExpression: Exp {
        Exp(.switchCase) {
            Self.isSelectedExpression
            Exp(.product) {
                Self.buildingExtrusionHeightExpression
                Self.selectedBuildingHeightScale
            }
            Self.buildingExtrusionHeightExpression
        }
    }

    private static var townhomeOverlayExtrusionHeightExpression: Exp {
        Exp(.max) {
            Exp(.toNumber) {
                Exp(.coalesce) {
                    Exp(.get) { "overlay_height" }
                    Exp(.get) { "height_m" }
                    Exp(.get) { "height" }
                    Self.defaultBuildingExtrusionHeight + Self.townhomeOverlayHeightLift
                }
            }
            Self.defaultBuildingExtrusionHeight + Self.townhomeOverlayHeightLift
        }
    }

    private static var townhomeOverlayExtrusionBaseExpression: Exp {
        Exp(.coalesce) {
            Exp(.get) { "overlay_base" }
            Self.buildingExtrusionBaseExpression
        }
    }

    private static var townhomeOverlayLineZOffsetExpression: Exp {
        Exp(.coalesce) {
            Exp(.get) { "overlay_height" }
            Exp(.get) { "height_m" }
            Exp(.get) { "height" }
            Self.defaultBuildingExtrusionHeight + Self.townhomeOverlayHeightLift
        }
    }

    private static var townhomeSegmentColorExpression: Exp {
        Exp(.switchCase) {
            Self.isSelectedExpression
            MapStatusColor.selectedHome

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "hot"
            }
            MapStatusColor.conversations

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "lead"
            }
            MapStatusColor.lead

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "appointment"
            }
            MapStatusColor.hotLead

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "hot_lead"
            }
            MapStatusColor.lead

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "future_seller"
            }
            MapStatusColor.hotLead

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "follow_up"
            }
            MapStatusColor.hotLead

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "flyer_unvisited"
            }
            MapStatusColor.flyerUntouched

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "do_not_knock"
            }
            MapStatusColor.doNotKnock

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "no_answer"
            }
            MapStatusColor.noOneHome

            Exp(.eq) {
                Exp(.get) { "segment_status" }
                "visited"
            }
            Exp(.switchCase) {
                Exp(.eq) {
                    Exp(.get) { "visit_owner" }
                    "teammate"
                }
                MapStatusColor.teammateTouched
                MapStatusColor.touched
            }

            MapStatusColor.untouched
        }
    }

    private static var buildingLinkOpacityExpression: Exp {
        Exp(.switchCase) {
            Self.isSelectedExpression
            1.0

            Exp(.eq) {
                Exp(.coalesce) {
                    Exp(.featureState) { "is_linked" }
                    Exp(.get) { "is_linked" }
                    false
                }
                true
            }
            1.0

            Exp(.eq) {
                Exp(.coalesce) {
                    Exp(.get) { "feature_status" }
                    ""
                }
                "matched"
            }
            1.0

            Exp(.gt) {
                Exp(.toNumber) {
                    Exp(.coalesce) {
                        Exp(.get) { "address_count" }
                        0
                    }
                }
                0
            }
            1.0

            0.5
        }
    }

    /// Opacity vs camera zoom for address circles.
    private static var addressMarkersZoomOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            11.8
            0.0
            12.2
            0.42
            12.8
            0.72
            13.5
            0.92
            14.2
            1.0
        }
    }

    private static var parcelOverviewFillOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            13.5
            0.0
            14.0
            0.06
            15.2
            0.10
            16.2
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.22
                0.16
            }
            18.0
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.16
                0.11
            }
            24.0
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.10
                0.07
            }
        }
    }

    private static var parcelOverviewLineOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            13.5
            0.0
            14.0
            0.22
            15.2
            0.48
            16.2
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                1.0
                0.78
            }
            18.0
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.90
                0.62
            }
            24.0
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.75
                0.50
            }
        }
    }

    private static var parcelOverviewLineWidthExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            13.5
            0.15
            15.0
            0.45
            16.2
            0.85
            20.0
            1.05
            24.0
            1.15
        }
    }

    private static var addressModeParcelLineWidthExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            0.0
            0.35
            13.2
            0.35
            15.0
            0.55
            16.2
            0.85
            20.0
            1.15
            24.0
            1.3
        }
    }

    private static var diamondParcelOverviewFillOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            13.5
            0.0
            14.0
            0.06
            15.2
            0.10
            17.4
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.18
                0.12
            }
            20.0
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.14
                0.08
            }
        }
    }

    private static var diamondParcelLineOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            13.5
            0.0
            14.0
            0.22
            15.2
            0.48
            17.4
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.9
                0.62
            }
            20.0
            Exp(.switchCase) {
                Self.isActiveStatusExpression
                0.82
                0.5
            }
        }
    }

    private static var parcelLinkedAddressColorExpression: Exp {
        Exp(.switchCase) {
            Self.isSelectedUnvisitedExpression
            MapStatusColor.selectedHome

            Exp(.gt) {
                Self.scansTotalExpression
                0
            }
            MapStatusColor.qrScanned

            Exp(.match) {
                Self.layerStatusExpression
                ["hot", "talked", "conversation"]
                MapStatusColor.conversations
                ["lead", "hot_lead"]
                MapStatusColor.lead
                ["appointment", "future_seller", "follow_up"]
                MapStatusColor.hotLead
                "flyer_unvisited"
                MapStatusColor.flyerUntouched
                "do_not_knock"
                MapStatusColor.doNotKnock
                "pending_visited"
                MapStatusColor.pendingVisited
                "no_answer"
                MapStatusColor.noOneHome
                "delivered"
                Exp(.switchCase) {
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "visit_owner" }
                            Exp(.get) { "visit_owner" }
                            ""
                        }
                        "teammate"
                    }
                    MapStatusColor.teammateTouched
                    MapStatusColor.touched
                }
                "visited"
                Exp(.switchCase) {
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "visit_owner" }
                            Exp(.get) { "visit_owner" }
                            ""
                        }
                        "teammate"
                    }
                    MapStatusColor.teammateTouched
                    MapStatusColor.touched
                }
                MapStatusColor.untouched
            }
        }
    }
    
    /// Opacity vs camera zoom for house number labels.
    private static var addressNumbersZoomOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            17.0
            0.0
            17.25
            0.28
            17.5
            0.62
            17.8
            0.9
            18.1
            1.0
        }
    }

    /// Opacity vs camera zoom for the compact house emblems. They bridge the gap before
    /// the larger address circles and house numbers become useful.
    private static var addressHouseIconsZoomOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            11.8
            0.0
            12.3
            0.9
            14.6
            0.9
            15.3
            0.0
        }
    }

    private static var selectedAddressOpacityExpression: Exp {
        return Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            11.8
            0.0
            12.2
            Exp(.switchCase) { Self.isSelectedExpression; 0.08; 0.0 }
            12.8
            Exp(.switchCase) { Self.isSelectedExpression; 0.12; 0.0 }
            13.5
            Exp(.switchCase) { Self.isSelectedExpression; 0.16; 0.0 }
            14.2
            Exp(.switchCase) { Self.isSelectedExpression; 0.18; 0.0 }
        }
    }

    private static func leadGlowOpacityExpression(statusKey: String = "status") -> Exp {
        Exp(.switchCase) {
            Exp(.match) {
                Exp(.coalesce) {
                    Exp(.featureState) { statusKey }
                    Exp(.get) { statusKey }
                    "none"
                }
                ["appointment", "future_seller", "follow_up", "hot_lead"]
                true
                false
            }
            0.82

            0.0
        }
    }
    
    // MARK: - Properties
    
    private weak var mapView: MapView?
    private let featuresService = MapFeaturesService.shared
    private let diamondGeometryProvider = VectorTileDiamondGeometryProvider()
    private var installedDiamondManifest: DiamondManifest?
    private var activeDiamondGeometrySignature: String?
    private var pendingDiamondGeometrySignature: String?
    private var failedDiamondGeometrySignatures: Set<String> = []
    private var desiredDiamondBuildingVisibility = true
    private var desiredDiamondAddressVisibility = true
    private var desiredDiamondAddressNumberVisibility: Bool?
    private var desiredAddressModeZoomVisibility = false
    private var lastAppliedDiamondBuildingVisibility: Bool?
    private var lastAppliedDiamondAddressVisibility: Bool?
    private var lastAppliedDiamondAddressNumberVisibility: Bool?
    private var diamondTerritoryBoundary: GeoJSONObject?
    private var diamondTerritoryBoundarySignature = "none"
    private var buildingFeatureStateCache: [String: [String: Any]] = [:]
    private var addressFeatureStateCache: [String: [String: Any]] = [:]
    private var townhomeOverlayFeatureIdsByBuildingIdentifier: [String: Set<String>] = [:]
    
    /// When false, 3D building extrusion layer is not added (campaign map shows flat map + addresses/roads only).
    var includeBuildingsLayer: Bool = true

    /// When false, address circle layer (purple pins) is not added; addresses source is still created and updated for logic.
    var includeAddressesLayer: Bool = true

    /// When false, campaign roads are still loaded into the source but we skip the visual overlay so
    /// the base map's native road styling stays unchanged.
    var showRoadOverlay: Bool = true

    var onDiamondGeometryInstallFailed: ((String, String) -> Void)?

    // Status filters
    var showQrScanned = true
    var showConversations = true
    var showTouched = true
    var showUntouched = true
    var showOrphans = true
    private var lastBuildingsSourceSignature: Int?
    private var lastTownhomeOverlaySignature: Int?
#if DEBUG
    private var lastTownhomeOverlayRenderedUnitCounts: [String: Int] = [:]
#endif
    private var lastAddressesSourceSignature: Int?
    private var lastRoadsSourceSignature: Int?
    private var lastParcelsSourceSignature: Int?
    private var cachedAddressPointSignature: Int?
    private var cachedAddressPolygonData: Data?
    private var lastAddressNumbersSourceSignature: Int?
    private var lastAddressNumbersVisible: Bool?
    private var lastTeammatePresenceSignature: Int?
    private var isInteractionQualityModeActive = false
    
    // MARK: - Init
    
    init(mapView: MapView) {
        self.mapView = mapView
    }
    
    // MARK: - Setup All Layers
    
    /// Set up all map layers (buildings if enabled, addresses, roads)
    func setupLayers() {
        resetSourceSignaturesForStyleReload()

        if includeBuildingsLayer {
            setupBuildingsLayer()
            setupTownhomeStatusLayer()
        }
        setupRoadsLayer()
        setupParcelsLayer()
        setupAddressesLayer()
        setupAddressNumbersLayer()
        setupAddressLabelHitboxLayer()
        setupManualAddressPreviewLayer()
        setupTeammatePresenceLayer()
        setupLighting()
    }

    private func resetSourceSignaturesForStyleReload() {
        lastBuildingsSourceSignature = nil
        lastTownhomeOverlaySignature = nil
#if DEBUG
        lastTownhomeOverlayRenderedUnitCounts = [:]
#endif
        lastAddressesSourceSignature = nil
        lastRoadsSourceSignature = nil
        lastParcelsSourceSignature = nil
        lastAddressNumbersSourceSignature = nil
        lastAddressNumbersVisible = nil
        lastTeammatePresenceSignature = nil
        // A Mapbox style reload drops custom vector-tile sources/layers even if the manifest did not change.
        installedDiamondManifest = nil
        activeDiamondGeometrySignature = nil
        lastAppliedDiamondBuildingVisibility = nil
        lastAppliedDiamondAddressVisibility = nil
        lastAppliedDiamondAddressNumberVisibility = nil
    }
    
    // MARK: - Buildings Layer (Fill Extrusion)
    
    /// Set up the 3D buildings fill-extrusion layer
    func setupBuildingsLayer() {
        guard let mapView = mapView else { return }
        
        // Add empty GeoJSON source
        var source = GeoJSONSource(id: Self.buildingsSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        
        // Enable promoteId for setFeatureState (real-time updates)
        source.promoteId2 = .constant("gers_id")
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added buildings source")
        } catch {
            print("❌ [MapLayer] Error adding buildings source: \(error)")
            return
        }
        
        // Create fill-extrusion layer
        var layer = FillExtrusionLayer(id: Self.buildingsLayerId, source: Self.buildingsSourceId)
        
        // Selected homes are recolored on the original extrusion so the full building
        // highlights cleanly without stacking a duplicate selected extrusion.
        layer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                Self.isSelectedExpression
                MapStatusColor.selectedHome

                // QR code: scans_total > 0 (purple)
                Exp(.gt) {
                    Self.scansTotalExpression
                    0
                }
                MapStatusColor.qrScanned
                
                // Talked: status == "hot"
                Exp(.eq) {
                    Self.layerStatusExpression
                    "hot"
                }
                MapStatusColor.conversations
                
                Exp(.eq) {
                    Self.layerStatusExpression
                    "lead"
                }
                MapStatusColor.lead

                Exp(.eq) {
                    Self.layerStatusExpression
                    "appointment"
                }
                MapStatusColor.hotLead

                Exp(.eq) {
                    Self.layerStatusExpression
                    "hot_lead"
                }
                MapStatusColor.lead

                Exp(.eq) {
                    Self.layerStatusExpression
                    "future_seller"
                }
                MapStatusColor.hotLead

                Exp(.eq) {
                    Self.layerStatusExpression
                    "follow_up"
                }
                MapStatusColor.hotLead

                Exp(.eq) {
                    Self.layerStatusExpression
                    "flyer_unvisited"
                }
                MapStatusColor.flyerUntouched

                Exp(.eq) {
                    Self.layerStatusExpression
                    "do_not_knock"
                }
                MapStatusColor.doNotKnock

                Exp(.eq) {
                    Self.layerStatusExpression
                    "no_answer"
                }
                MapStatusColor.noOneHome

                // Pending local confirmation.
                Exp(.eq) {
                    Self.layerStatusExpression
                    "pending_visited"
                }
                MapStatusColor.pendingVisited

                // Touched: status == "visited"
                Exp(.eq) {
                    Self.layerStatusExpression
                    "visited"
                }
                Exp(.switchCase) {
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "visit_owner" }
                            Exp(.get) { "visit_owner" }
                            ""
                        }
                        "teammate"
                    }
                    MapStatusColor.teammateTouched
                    MapStatusColor.touched
                }

                // Default: unvisited slate
                MapStatusColor.untouched
            }
        )
        
        layer.fillExtrusionHeight = .expression(Self.selectedBuildingExtrusionHeightExpression)
        layer.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
        layer.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
        
        // Base at ground level
        layer.fillExtrusionBase = .expression(Self.buildingExtrusionBaseExpression)
        
        // Mapbox iOS rejects data expressions on fill-extrusion-opacity. Keep
        // opacity constant and let the color expression carry status/selection.
        layer.fillExtrusionOpacity = .constant(1.0)
        
        // Keep extrusion sides flat. The Mapbox vertical gradient can create triangular
        // facet artifacts that become very visible when a selected building is brightened.
        layer.fillExtrusionVerticalGradient = .constant(false)
        
        // Min zoom (only show when zoomed in)
        layer.minZoom = 12
        
        // Only polygons (defense in depth: avoid FillBucket LineString errors)
        layer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        do {
            try mapView.mapboxMap.addLayer(layer)
            print("✅ [MapLayer] Added buildings fill-extrusion layer")
        } catch {
            print("❌ [MapLayer] Error adding buildings layer: \(error)")
        }

        var selectedGlowLayer = LineLayer(id: Self.buildingsSelectedGlowLayerId, source: Self.buildingsSourceId)
        selectedGlowLayer.lineColor = .constant(StyleColor(MapStatusColor.selectedHomeGlow))
        selectedGlowLayer.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                12
                1.2
                16
                3.0
                20
                5.0
            }
        )
        selectedGlowLayer.lineBlur = .constant(4.0)
        // Selection is shown by recoloring the full extrusion; keep outline layers silent.
        selectedGlowLayer.lineOpacity = .constant(0.0)
        selectedGlowLayer.lineOpacityTransition = StyleTransition(duration: 0.2, delay: 0)
        selectedGlowLayer.minZoom = 12
        selectedGlowLayer.filter = layer.filter

        do {
            try mapView.mapboxMap.addLayer(selectedGlowLayer, layerPosition: .above(Self.buildingsLayerId))
            print("✅ [MapLayer] Added selected building glow layer")
        } catch {
            print("❌ [MapLayer] Error adding selected building glow layer: \(error)")
        }

        // Lead status is communicated by the building fill color itself. Avoid a separate
        // always-on line layer so highlighted homes stay clean unless selected.
    }

    /// Set up a townhouse-only overlay layer that can render mixed per-unit statuses
    /// on top of a single building footprint.
    func setupTownhomeStatusLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.townhomeOverlaySourceId)
        source.data = .featureCollection(FeatureCollection(features: []))

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding townhouse overlay source: \(error)")
            return
        }

        var layer = FillExtrusionLayer(id: Self.townhomeOverlayLayerId, source: Self.townhomeOverlaySourceId)
        layer.fillExtrusionColor = .expression(Self.townhomeSegmentColorExpression)
        layer.fillExtrusionHeight = .expression(Self.townhomeOverlayExtrusionHeightExpression)
        layer.fillExtrusionBase = .expression(Self.townhomeOverlayExtrusionBaseExpression)
        // Townhome segments must render as their actual status color. A translucent
        // plate blends red/coral statuses into the green building underneath.
        layer.fillExtrusionOpacity = .constant(1.0)
        layer.fillExtrusionVerticalGradient = .constant(false)
        layer.minZoom = 12
        layer.filter = Self.townhomeOverlayFilter(
            showConversations: true,
            showTouched: true,
            showUntouched: true
        )

        do {
            try mapView.mapboxMap.addLayer(layer)
            print("✅ [MapLayer] Added townhouse overlay layer")
        } catch {
            print("❌ [MapLayer] Error adding townhouse overlay layer: \(error)")
            return
        }

        var sliceOutlineLayer = LineLayer(id: Self.townhomeSliceOutlineLayerId, source: Self.townhomeOverlaySourceId)
        sliceOutlineLayer.lineColor = .constant(StyleColor(UIColor.black))
        sliceOutlineLayer.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                12
                1.8
                16
                2.8
                20
                4.0
            }
        )
        sliceOutlineLayer.lineOpacity = .constant(0.0)
        sliceOutlineLayer.lineEmissiveStrength = .constant(1.0)
        sliceOutlineLayer.lineElevationReference = .constant(.ground)
        sliceOutlineLayer.lineZOffset = .expression(Self.townhomeOverlayLineZOffsetExpression)
        sliceOutlineLayer.lineJoin = .constant(.round)
        sliceOutlineLayer.lineCap = .constant(.round)
        sliceOutlineLayer.minZoom = 12
        sliceOutlineLayer.filter = Self.townhomeOverlayFilter(
            showConversations: true,
            showTouched: true,
            showUntouched: true
        )

        do {
            try mapView.mapboxMap.addLayer(sliceOutlineLayer, layerPosition: .above(Self.townhomeOverlayLayerId))
            print("✅ [MapLayer] Added townhouse slice outline layer")
        } catch {
            print("❌ [MapLayer] Error adding townhouse slice outline layer: \(error)")
        }

        var dividerStripLayer = FillExtrusionLayer(id: Self.townhomeDividerStripLayerId, source: Self.townhomeOverlaySourceId)
        dividerStripLayer.fillExtrusionColor = .constant(StyleColor(UIColor.black))
        dividerStripLayer.fillExtrusionHeight = .expression(Self.townhomeOverlayExtrusionHeightExpression)
        dividerStripLayer.fillExtrusionBase = .expression(Self.townhomeOverlayExtrusionBaseExpression)
        dividerStripLayer.fillExtrusionOpacity = .constant(0.0)
        dividerStripLayer.fillExtrusionVerticalGradient = .constant(false)
        dividerStripLayer.minZoom = 12
        dividerStripLayer.filter = Self.townhomeDividerStripFilter()

        do {
            try mapView.mapboxMap.addLayer(dividerStripLayer, layerPosition: .above(Self.townhomeOverlayLayerId))
            print("✅ [MapLayer] Added townhouse divider strip layer")
        } catch {
            print("❌ [MapLayer] Error adding townhouse divider strip layer: \(error)")
        }

        var dividerLayer = LineLayer(id: Self.townhomeDividerLayerId, source: Self.townhomeOverlaySourceId)
        dividerLayer.lineColor = .constant(StyleColor(UIColor(white: 0.02, alpha: 1.0)))
        dividerLayer.lineWidth = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                12
                1.0
                16
                1.6
                20
                2.2
            }
        )
        dividerLayer.lineBlur = .constant(0.25)
        dividerLayer.lineOpacity = .constant(0.0)
        dividerLayer.lineEmissiveStrength = .constant(0.35)
        dividerLayer.lineElevationReference = .constant(.ground)
        dividerLayer.lineZOffset = .expression(Self.townhomeOverlayLineZOffsetExpression)
        dividerLayer.lineJoin = .constant(.round)
        dividerLayer.lineCap = .constant(.butt)
        dividerLayer.minZoom = 12
        dividerLayer.filter = Self.townhomeDividerFilter()

        do {
            try mapView.mapboxMap.addLayer(dividerLayer, layerPosition: .above(Self.townhomeDividerStripLayerId))
            print("✅ [MapLayer] Added townhouse divider layer")
        } catch {
            print("❌ [MapLayer] Error adding townhouse divider layer: \(error)")
        }
    }
    
    // MARK: - Roads Layer (Line)
    
    /// Set up the roads line layer
    func setupRoadsLayer() {
        guard let mapView = mapView else { return }
        
        // Add empty GeoJSON source
        var source = GeoJSONSource(id: Self.roadsSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added roads source")
        } catch {
            print("❌ [MapLayer] Error adding roads source: \(error)")
            return
        }
        
        guard showRoadOverlay else {
            print("ℹ️ [MapLayer] Road overlay hidden; campaign roads remain loaded in source only")
            return
        }

        // Create line layer
        var layer = LineLayer(id: Self.roadsLayerId, source: Self.roadsSourceId)
        
        // Road color based on class
        layer.lineColor = .expression(
            Exp(.match) {
                Exp(.get) { "class" }
                // Primary roads
                ["primary", "secondary", "tertiary"]
                MapStatusColor.roadPrimary
                // Default
                MapStatusColor.roadSecondary
            }
        )
        
        // Road width based on class
        layer.lineWidth = .expression(
            Exp(.match) {
                Exp(.get) { "class" }
                ["primary"]
                4.0
                ["secondary"]
                3.0
                ["tertiary"]
                2.5
                // Default
                2.0
            }
        )
        
        layer.lineCap = .constant(.round)
        layer.lineJoin = .constant(.round)
        layer.minZoom = 12
        
        do {
            if includeBuildingsLayer {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .below(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added roads line layer")
        } catch {
            print("❌ [MapLayer] Error adding roads layer: \(error)")
        }
    }

    // MARK: - Parcels Layer (GeoJSON Fill)

    func setupParcelsLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.parcelsSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        source.promoteId2 = .constant("address_id")

        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added parcels source")
        } catch {
            print("❌ [MapLayer] Error adding parcels source: \(error)")
            return
        }

        var fillLayer = FillLayer(id: Self.parcelsFillLayerId, source: Self.parcelsSourceId)
        fillLayer.fillColor = .expression(Self.parcelLinkedAddressColorExpression)
        fillLayer.fillOpacity = .expression(Self.parcelOverviewFillOpacityExpression)
        fillLayer.fillAntialias = .constant(false)
        fillLayer.minZoom = Self.parcelsOverviewMinZoom
        fillLayer.maxZoom = Self.parcelsOverviewMaxZoom
        fillLayer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }

        do {
            let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
            if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(fillLayer, layerPosition: .below(Self.buildingsLayerId))
            } else if layerIds.contains(Self.addressesLayerId) {
                try mapView.mapboxMap.addLayer(fillLayer, layerPosition: .below(Self.addressesLayerId))
            } else {
                try mapView.mapboxMap.addLayer(fillLayer)
            }
            print("✅ [MapLayer] Added parcels fill layer")
        } catch {
            print("❌ [MapLayer] Error adding parcels fill layer: \(error)")
        }

        var lineLayer = LineLayer(id: Self.parcelsLineLayerId, source: Self.parcelsSourceId)
        lineLayer.lineColor = .expression(Self.parcelLinkedAddressColorExpression)
        lineLayer.lineOpacity = .expression(Self.parcelOverviewLineOpacityExpression)
        lineLayer.lineWidth = .expression(
            Self.parcelOverviewLineWidthExpression
        )
        lineLayer.minZoom = Self.parcelsOverviewMinZoom
        lineLayer.maxZoom = Self.parcelsOverviewMaxZoom
        lineLayer.filter = fillLayer.filter

        do {
            let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
            if layerIds.contains(Self.parcelsFillLayerId) {
                try mapView.mapboxMap.addLayer(lineLayer, layerPosition: .above(Self.parcelsFillLayerId))
            } else {
                try mapView.mapboxMap.addLayer(lineLayer)
            }
            print("✅ [MapLayer] Added parcels outline layer")
        } catch {
            print("❌ [MapLayer] Error adding parcels outline layer: \(error)")
        }
    }

    // MARK: - Addresses Layer (3D Circle Extrusions)
    
    /// Set up the addresses layer as 3D circle polygons (web-aligned layer IDs preserved for compatibility).
    func setupAddressesLayer() {
        guard let mapView = mapView else { return }
        
        // Add empty GeoJSON source (promoteId so we can use setFeatureState for status colors)
        var source = GeoJSONSource(id: Self.addressesSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        source.promoteId2 = .constant("id")
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added addresses source (\(Self.addressesSourceId))")
        } catch {
            print("❌ [MapLayer] Error adding addresses source: \(error)")
            return
        }
        
        // Always add the layer so it exists for visibility toggling (includeAddressesLayer is only for default visibility;
        // if we skip adding when false, the layer can be missing if updateLayerVisibility ran before style loaded).
        
        // Create fill-extrusion layer for address points; color by feature-state (status / scans_total)
        // Support both normalized layer status (hot, visited, not_visited) and raw API status (talked, no_answer, etc.)
        // Selection is a subtle overlay, not the base fill, so state changes remain visible while selected.
        var layer = FillExtrusionLayer(id: Self.addressesLayerId, source: Self.addressesSourceId)
        layer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "scans_total" }
                        Exp(.get) { "scans_total" }
                        0
                    }
                    0
                }
                MapStatusColor.qrScanned
                // Blue: conversation / talked (normalized "hot" or raw)
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot"
                }
                MapStatusColor.conversations
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "lead"
                }
                MapStatusColor.lead
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "talked"
                }
                MapStatusColor.conversations
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "appointment"
                }
                MapStatusColor.hotLead
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot_lead"
                }
                MapStatusColor.lead
                // Do not knock: gray (distinct from visited green)
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "flyer_unvisited"
                }
                MapStatusColor.flyerUntouched
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "do_not_knock"
                }
                MapStatusColor.doNotKnock
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "pending_visited"
                }
                MapStatusColor.pendingVisited
                // Green: touched / visited / delivered
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "visited"
                }
                Exp(.switchCase) {
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "visit_owner" }
                            Exp(.get) { "visit_owner" }
                            ""
                        }
                        "teammate"
                    }
                    MapStatusColor.teammateTouched
                    MapStatusColor.touched
                }
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "no_answer"
                }
                MapStatusColor.noOneHome
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "delivered"
                }
                Exp(.switchCase) {
                    Exp(.eq) {
                        Exp(.coalesce) {
                            Exp(.featureState) { "visit_owner" }
                            Exp(.get) { "visit_owner" }
                            ""
                        }
                        "teammate"
                    }
                    MapStatusColor.teammateTouched
                    MapStatusColor.touched
                }
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "future_seller"
                }
                MapStatusColor.hotLead
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "follow_up"
                }
                MapStatusColor.hotLead
                MapStatusColor.untouched
            }
        )
        layer.fillExtrusionOpacity = .expression(Self.addressMarkersZoomOpacityExpression)
        layer.fillExtrusionHeight = .expression(Self.addressMarkerExtrusionHeightExpression)
        layer.fillExtrusionBase = .expression(Self.addressMarkerExtrusionBaseExpression)
        layer.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
        layer.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
        layer.fillExtrusionVerticalGradient = .constant(false)
        layer.minZoom = Self.addressMarkersLayerMinZoom
        layer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        do {
            if includeBuildingsLayer {
                let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
                if layerIds.contains(Self.townhomeOverlayLayerId) {
                    try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.townhomeOverlayLayerId))
                } else {
                    try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.buildingsLayerId))
                }
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added addresses extrusion layer (\(Self.addressesLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding addresses layer: \(error)")
        }

        var selectedLayer = FillExtrusionLayer(id: Self.selectedAddressesLayerId, source: Self.addressesSourceId)
        selectedLayer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                Self.isSelectedUnvisitedExpression
                MapStatusColor.selectedHome
                UIColor.clear
            }
        )
        selectedLayer.fillExtrusionOpacity = .constant(1.0)
        selectedLayer.fillExtrusionHeight = .expression(Self.addressMarkerExtrusionHeightExpression)
        selectedLayer.fillExtrusionBase = .expression(Self.addressMarkerExtrusionBaseExpression)
        selectedLayer.fillExtrusionColorTransition = StyleTransition(duration: 0.18, delay: 0)
        selectedLayer.fillExtrusionHeightTransition = StyleTransition(duration: 0.18, delay: 0)
        selectedLayer.fillExtrusionVerticalGradient = .constant(false)
        selectedLayer.minZoom = Self.addressMarkersLayerMinZoom
        selectedLayer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }

        do {
            let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
            if layerIds.contains(Self.addressesLayerId) {
                try mapView.mapboxMap.addLayer(selectedLayer, layerPosition: .above(Self.addressesLayerId))
            } else if layerIds.contains(Self.townhomeOverlayLayerId) {
                try mapView.mapboxMap.addLayer(selectedLayer, layerPosition: .above(Self.townhomeOverlayLayerId))
            } else if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(selectedLayer, layerPosition: .above(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(selectedLayer)
            }
            print("✅ [MapLayer] Added selected address overlay layer (\(Self.selectedAddressesLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding selected address overlay layer: \(error)")
        }

        // Keep address markers extrusion-only for lead/follow-up states; no ground outline.
    }

    private func setupAddressNumbersLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.addressNumbersSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        source.promoteId2 = .constant("id")

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding address numbers source: \(error)")
            return
        }

        var layer = SymbolLayer(id: Self.addressNumbersLayerId, source: Self.addressNumbersSourceId)
        layer.textField = .expression(Exp(.get) { "house_number_label" })
        layer.textSize = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                17
                11.5
                20
                15
            }
        )
        layer.textColor = .constant(StyleColor(.white))
        layer.textHaloColor = .constant(StyleColor(.black))
        layer.textHaloWidth = .constant(1.4)
        layer.textHaloBlur = .constant(0.4)
        layer.textAnchor = .constant(.center)
        layer.textJustify = .constant(.center)
        layer.textOffset = .constant([0, -0.35])
        layer.textPitchAlignment = .constant(.viewport)
        layer.textRotationAlignment = .constant(.viewport)
        layer.textVariableAnchor = .constant([.center])
        layer.symbolPlacement = .constant(.point)
        layer.symbolSortKey = .expression(
            Exp(.coalesce) {
                Exp(.get) { "label_priority" }
                100
            }
        )
        layer.symbolSpacing = .constant(32)
        layer.symbolAvoidEdges = .constant(true)
        layer.symbolZOrder = .constant(.auto)
        layer.symbolZElevate = .constant(true)
        layer.symbolElevationReference = .constant(.ground)
        layer.symbolZOffset = .expression(
            Exp(.coalesce) {
                Exp(.get) { "label_z_offset" }
                Self.addressNumberRoofClearance
            }
        )
        layer.textAllowOverlap = .constant(true)
        layer.textIgnorePlacement = .constant(true)
        layer.textOptional = .constant(false)
        layer.textOcclusionOpacity = .constant(1.0)
        layer.textOpacity = .expression(Self.addressNumbersZoomOpacityExpression)
        layer.minZoom = Self.addressNumbersLayerMinZoom
        layer.visibility = .constant(.none)
        layer.filter = Exp(.all) {
            Exp(.eq) {
                Exp(.geometryType)
                "Point"
            }
            Exp(.neq) {
                Exp(.coalesce) {
                    Exp(.get) { "house_number_label" }
                    ""
                }
                ""
            }
        }

        do {
            let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
            if layerIds.contains(Self.manualAddressPreviewLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.manualAddressPreviewLayerId))
            } else if layerIds.contains(Self.selectedAddressesLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.selectedAddressesLayerId))
            } else if layerIds.contains(Self.townhomeOverlayLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.townhomeOverlayLayerId))
            } else if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added address numbers symbol layer (\(Self.addressNumbersLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding address numbers layer: \(error)")
        }
    }

    private func setupAddressHouseIconLayer() {
        guard let mapView = mapView else { return }

        do {
            try mapView.mapboxMap.addImage(Self.makeAddressHouseIconImage(), id: Self.addressHouseIconImageId)
        } catch {
            print("⚠️ [MapLayer] Address house emblem image already installed or failed to install: \(error)")
        }

        var layer = SymbolLayer(id: Self.addressHouseIconLayerId, source: Self.addressNumbersSourceId)
        layer.iconImage = .constant(.name(Self.addressHouseIconImageId))
        layer.iconSize = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                12.0
                0.78
                15.0
                1.0
            }
        )
        layer.iconOpacity = .expression(Self.addressHouseIconsZoomOpacityExpression)
        layer.iconAllowOverlap = .constant(false)
        layer.iconIgnorePlacement = .constant(false)
        layer.iconOptional = .constant(false)
        layer.iconPitchAlignment = .constant(.viewport)
        layer.iconRotationAlignment = .constant(.viewport)
        layer.symbolPlacement = .constant(.point)
        layer.symbolSpacing = .constant(42)
        layer.symbolAvoidEdges = .constant(true)
        layer.symbolSortKey = .expression(
            Exp(.coalesce) {
                Exp(.get) { "label_priority" }
                100
            }
        )
        layer.minZoom = 11.8
        layer.maxZoom = 15.4
        layer.visibility = .constant(.visible)
        layer.filter = Exp(.eq) {
            Exp(.geometryType)
            "Point"
        }

        do {
            let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
            if layerIds.contains(Self.selectedAddressesLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.selectedAddressesLayerId))
            } else if layerIds.contains(Self.townhomeOverlayLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.townhomeOverlayLayerId))
            } else if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added address house emblem layer (\(Self.addressHouseIconLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding address house emblem layer: \(error)")
        }
    }

    private func setupAddressLabelHitboxLayer() {
        guard let mapView = mapView else { return }

        var layer = CircleLayer(id: Self.addressLabelHitboxLayerId, source: Self.addressNumbersSourceId)
        layer.circleRadius = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                16
                14
                18
                18
                20
                24
            }
        )
        layer.circleColor = .constant(StyleColor(.white))
        layer.circleOpacity = .constant(0.01)
        layer.circleStrokeOpacity = .constant(0)
        layer.minZoom = Self.addressNumbersLayerMinZoom
        layer.visibility = .constant(.none)
        layer.filter = Exp(.all) {
            Exp(.eq) {
                Exp(.geometryType)
                "Point"
            }
            Exp(.neq) {
                Exp(.coalesce) {
                    Exp(.get) { "house_number_label" }
                    ""
                }
                ""
            }
        }

        do {
            if mapView.mapboxMap.layerExists(withId: Self.addressNumbersLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .below(Self.addressNumbersLayerId))
            } else if mapView.mapboxMap.layerExists(withId: Self.selectedAddressesLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.selectedAddressesLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added address label hitbox layer (\(Self.addressLabelHitboxLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding address label hitbox layer: \(error)")
        }
    }

    private static func makeAddressHouseIconImage() -> UIImage {
        let canvasSize = CGSize(width: 30, height: 30)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 2, dy: 2)
            let cgContext = context.cgContext
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 1.5),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.28).cgColor
            )

            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()

            cgContext.setShadow(offset: .zero, blur: 0, color: UIColor.clear.cgColor)
            MapStatusColor.addressMarker.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()

            let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            let symbolRect = CGRect(x: 8, y: 8, width: 14, height: 14)
            UIImage(systemName: "house.fill", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: symbolRect)
        }
    }

    func setupManualAddressPreviewLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.manualAddressPreviewSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding manual address preview source: \(error)")
            return
        }

        var layer = FillLayer(id: Self.manualAddressPreviewLayerId, source: Self.manualAddressPreviewSourceId)
        layer.fillColor = .constant(StyleColor(UIColor(hex: "#f59e0b")!))
        layer.fillOpacity = .constant(0.92)
        layer.fillAntialias = .constant(true)
        layer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }

        let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))

        do {
            if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.buildingsLayerId))
            } else if layerIds.contains(Self.addressesLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.addressesLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
        } catch {
            print("❌ [MapLayer] Error adding manual address preview layer: \(error)")
        }
    }

    func setupTeammatePresenceLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.teammatePresenceSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding teammate presence source: \(error)")
            return
        }

        var circles = CircleLayer(id: Self.teammatePresenceCircleLayerId, source: Self.teammatePresenceSourceId)
        circles.circleColor = .expression(
            Exp(.switchCase) {
                Exp(.eq) {
                    Exp(.get) { "presence_status" }
                    "paused"
                }
                UIColor(hex: "#f59e0b") ?? .systemOrange

                Exp(.eq) {
                    Exp(.get) { "freshness" }
                    "stale"
                }
                UIColor(hex: "#6b7280") ?? .systemGray

                UIColor(hex: "#14b8a6") ?? .systemTeal
            }
        )
        circles.circleOpacity = .expression(
            Exp(.coalesce) {
                Exp(.get) { "opacity" }
                1.0
            }
        )
        circles.circleStrokeColor = .constant(StyleColor(.white))
        circles.circleStrokeOpacity = .expression(
            Exp(.coalesce) {
                Exp(.get) { "opacity" }
                1.0
            }
        )
        circles.circleStrokeWidth = .constant(1.5)
        circles.circleRadius = .expression(
            Exp(.switchCase) {
                Exp(.eq) {
                    Exp(.get) { "freshness" }
                    "stale"
                }
                11
                13
            }
        )

        var labels = SymbolLayer(id: Self.teammatePresenceLabelLayerId, source: Self.teammatePresenceSourceId)
        labels.textField = .expression(Exp(.get) { "initials" })
        labels.textColor = .constant(StyleColor(.white))
        labels.textSize = .constant(11)
        labels.textAllowOverlap = .constant(true)
        labels.textIgnorePlacement = .constant(true)
        labels.textOpacity = .expression(
            Exp(.coalesce) {
                Exp(.get) { "opacity" }
                1.0
            }
        )

        do {
            try mapView.mapboxMap.addLayer(circles)
            try mapView.mapboxMap.addLayer(labels)
        } catch {
            print("❌ [MapLayer] Error adding teammate presence layers: \(error)")
        }
    }
    
    // MARK: - Lighting
    
    /// Set up 3D lighting for fill-extrusions
    func setupLighting() {
        guard let mapView = mapView else { return }
        
        // Keep status colors legible on every face. Strong directional shadows make
        // selected/statused homes look like they have random dark panels.
        var ambientLight = AmbientLight()
        ambientLight.color = .constant(StyleColor(.white))
        ambientLight.intensity = .constant(0.92)
        
        // Configure directional light
        var directionalLight = DirectionalLight()
        directionalLight.color = .constant(StyleColor(.white))
        directionalLight.intensity = .constant(0.18)
        directionalLight.direction = .constant([210, 30]) // Azimuth, Altitude
        directionalLight.castShadows = .constant(false)
        
        do {
            try mapView.mapboxMap.setLights(ambient: ambientLight, directional: directionalLight)
            print("✅ [MapLayer] Configured 3D lighting")
        } catch {
            print("❌ [MapLayer] Error setting lights: \(error)")
        }
    }
    
    // MARK: - Update Data

    func updateDiamondTerritoryBoundary(_ boundary: GeoJSONObject?, signature: String) {
        guard diamondTerritoryBoundarySignature != signature else { return }
        diamondTerritoryBoundarySignature = signature
        diamondTerritoryBoundary = boundary

        guard let mapView else { return }
        do {
            try diamondGeometryProvider.applyTerritoryBoundary(boundary, on: mapView)
            print("🧪 [MAP_DEBUG] pmtiles_scope_updated scope=\(boundary == nil ? "none" : "campaign_polygon") signature=\(signature)")
        } catch {
            print("❌ [DIAMOND] Error applying Diamond territory scope: \(error)")
            print("🧪 [MAP_DEBUG] pmtiles_scope_failed scope=\(boundary == nil ? "none" : "campaign_polygon") error=\(error.localizedDescription)")
        }
    }

    func updateDiamondGeometry(manifest: DiamondManifest?) {
        guard let mapView = mapView else { return }

        guard let manifest else {
            let hadDiamondGeometry = installedDiamondManifest != nil ||
                activeDiamondGeometrySignature != nil ||
                pendingDiamondGeometrySignature != nil
            installedDiamondManifest = nil
            activeDiamondGeometrySignature = nil
            pendingDiamondGeometrySignature = nil
            failedDiamondGeometrySignatures.removeAll()
            lastAppliedDiamondBuildingVisibility = nil
            lastAppliedDiamondAddressVisibility = nil
            lastAppliedDiamondAddressNumberVisibility = nil
            if hadDiamondGeometry {
                print("🧪 [MAP_DEBUG] renderer_clear renderer=pmtiles_vector reason=manifest_nil")
            }
            do {
                try diamondGeometryProvider.removeGeometry(from: mapView)
            } catch {
                print("❌ [DIAMOND] Error removing Diamond geometry: \(error)")
            }
            return
        }

        let signature = [
            manifest.campaignId.lowercased(),
            manifest.geometryProvider ?? "",
            manifest.vectorTileUrlTemplate ?? "",
            manifest.addressVectorTileUrlTemplate ?? "",
            manifest.parcelVectorTileUrlTemplate ?? "",
            String(manifest.geometryVersion ?? 0),
            manifest.geometryEtag ?? ""
        ].joined(separator: "|")

        guard !failedDiamondGeometrySignatures.contains(signature) else {
            applyDiamondGeometryVisibilityIfNeeded()
            return
        }

        guard activeDiamondGeometrySignature != signature,
              pendingDiamondGeometrySignature != signature else {
            applyDiamondGeometryVisibilityIfNeeded()
            return
        }

        pendingDiamondGeometrySignature = signature
        let debugInstallStartedAt = Date()
        print(
            "🧪 [MAP_DEBUG] pmtiles_install_start campaign=\(manifest.campaignId) " +
            "buildingTiles=\(manifest.vectorTileUrlTemplate != nil) " +
            "addressTiles=\(manifest.addressVectorTileUrlTemplate != nil) " +
            "parcelTiles=\(manifest.parcelVectorTileUrlTemplate != nil) " +
            "buildingLayer=\(manifest.sourceLayers?.buildings ?? "nil") " +
            "addressCirclesLayer=\(manifest.sourceLayers?.addressCircles ?? "nil")"
        )

        Task { @MainActor [weak self, weak mapView] in
            guard let self, let mapView else { return }
            do {
                try await self.diamondGeometryProvider.installGeometry(
                    for: manifest.campaignId,
                    manifest: manifest,
                    on: mapView,
                    territoryBoundary: self.diamondTerritoryBoundary
                )
                self.installedDiamondManifest = manifest
                self.activeDiamondGeometrySignature = signature
                self.pendingDiamondGeometrySignature = nil
                self.lastAppliedDiamondBuildingVisibility = nil
                self.lastAppliedDiamondAddressVisibility = nil
                self.lastAppliedDiamondAddressNumberVisibility = nil
                self.applyDiamondGeometryVisibilityIfNeeded()
                self.updateDiamondAddressModeZoomVisibility(isAddressMode: self.desiredAddressModeZoomVisibility)
                self.replayCachedFeatureStates(reason: "diamond_install")
                print("💎 [DIAMOND] Installed vector tile geometry for campaign \(manifest.campaignId)")
                print("🧪 [MAP_DEBUG] pmtiles_install_done campaign=\(manifest.campaignId) ms=\(Int(Date().timeIntervalSince(debugInstallStartedAt) * 1000)) renderer=pmtiles_vector")
            } catch {
                self.failedDiamondGeometrySignatures.insert(signature)
                self.installedDiamondManifest = nil
                self.activeDiamondGeometrySignature = nil
                self.pendingDiamondGeometrySignature = nil
                self.lastAppliedDiamondBuildingVisibility = nil
                self.lastAppliedDiamondAddressVisibility = nil
                self.lastAppliedDiamondAddressNumberVisibility = nil
                do {
                    try self.diamondGeometryProvider.removeGeometry(from: mapView)
                } catch {
                    print("❌ [DIAMOND] Error removing failed Diamond geometry: \(error)")
                }
                print("❌ [DIAMOND] Error installing vector tile geometry: \(error)")
                print("🧪 [MAP_DEBUG] pmtiles_install_failed campaign=\(manifest.campaignId) ms=\(Int(Date().timeIntervalSince(debugInstallStartedAt) * 1000)) error=\(error.localizedDescription)")
                self.onDiamondGeometryInstallFailed?(manifest.campaignId, error.localizedDescription)
            }
        }
    }

    func setDiamondGeometryVisibility(_ isVisible: Bool, addressNumbers: Bool? = nil) {
        desiredDiamondBuildingVisibility = isVisible
        desiredDiamondAddressVisibility = isVisible
        desiredDiamondAddressNumberVisibility = addressNumbers
        applyDiamondGeometryVisibilityIfNeeded()
    }

    func setDiamondGeometryVisibility(buildings: Bool, addresses: Bool, addressNumbers: Bool? = nil) {
        desiredDiamondBuildingVisibility = buildings
        desiredDiamondAddressVisibility = addresses
        desiredDiamondAddressNumberVisibility = addressNumbers
        applyDiamondGeometryVisibilityIfNeeded()
    }

    private func applyDiamondGeometryVisibilityIfNeeded() {
        guard let mapView = mapView else { return }
        let layerIds = [
            VectorTileDiamondGeometryProvider.parcelFillLayerId,
            VectorTileDiamondGeometryProvider.parcelLineLayerId,
            VectorTileDiamondGeometryProvider.buildingFillLayerId,
            VectorTileDiamondGeometryProvider.buildingLineLayerId,
            VectorTileDiamondGeometryProvider.buildingLeadGlowLayerId,
            VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId,
            VectorTileDiamondGeometryProvider.addressCircleLayerId,
            VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId,
            VectorTileDiamondGeometryProvider.addressNumberLayerId
        ]

        let existingLayerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
        guard layerIds.contains(where: existingLayerIds.contains) else { return }
        guard lastAppliedDiamondBuildingVisibility != desiredDiamondBuildingVisibility ||
              lastAppliedDiamondAddressVisibility != desiredDiamondAddressVisibility ||
              lastAppliedDiamondAddressNumberVisibility != desiredDiamondAddressNumberVisibility else { return }

        let shouldShowAddressNumbers = desiredDiamondAddressNumberVisibility ?? desiredDiamondAddressVisibility

        for layerId in layerIds where existingLayerIds.contains(layerId) {
            let isAddressCircleLayer = layerId == VectorTileDiamondGeometryProvider.addressCircleLayerId ||
                layerId == VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId
            let isAddressNumberLayer = layerId == VectorTileDiamondGeometryProvider.addressNumberLayerId
            let isBuildingAddressNumberLayer = layerId == VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId
            let isParcelLayer = layerId == VectorTileDiamondGeometryProvider.parcelFillLayerId ||
                layerId == VectorTileDiamondGeometryProvider.parcelLineLayerId
            let shouldShow: Bool
            if isParcelLayer {
                shouldShow = desiredDiamondBuildingVisibility || desiredDiamondAddressVisibility
            } else if isAddressCircleLayer {
                shouldShow = desiredDiamondAddressVisibility
            } else if isAddressNumberLayer {
                shouldShow = shouldShowAddressNumbers && desiredDiamondAddressVisibility
            } else if isBuildingAddressNumberLayer {
                shouldShow = shouldShowAddressNumbers && desiredDiamondBuildingVisibility
            } else {
                shouldShow = desiredDiamondBuildingVisibility
            }
            let visibility: Visibility = shouldShow ? .visible : .none

            if layerId == VectorTileDiamondGeometryProvider.parcelFillLayerId {
                try? mapView.mapboxMap.updateLayer(withId: layerId, type: FillLayer.self) {
                    $0.visibility = .constant(visibility)
                }
            } else if layerId == VectorTileDiamondGeometryProvider.buildingFillLayerId {
                try? mapView.mapboxMap.updateLayer(withId: layerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(visibility)
                }
            } else if layerId == VectorTileDiamondGeometryProvider.addressCircleLayerId ||
                        layerId == VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId {
                if installedDiamondManifest?.sourceLayers?.addressCircles?.isEmpty == false {
                    try? mapView.mapboxMap.updateLayer(withId: layerId, type: FillExtrusionLayer.self) {
                        $0.visibility = .constant(visibility)
                    }
                } else {
                    try? mapView.mapboxMap.updateLayer(withId: layerId, type: CircleLayer.self) {
                        $0.visibility = .constant(visibility)
                    }
                }
            } else if layerId == VectorTileDiamondGeometryProvider.addressNumberLayerId ||
                        layerId == VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId {
                try? mapView.mapboxMap.updateLayer(withId: layerId, type: SymbolLayer.self) {
                    $0.visibility = .constant(visibility)
                }
            } else {
                try? mapView.mapboxMap.updateLayer(withId: layerId, type: LineLayer.self) {
                    $0.visibility = .constant(visibility)
                }
            }
        }

        lastAppliedDiamondBuildingVisibility = desiredDiamondBuildingVisibility
        lastAppliedDiamondAddressVisibility = desiredDiamondAddressVisibility
        lastAppliedDiamondAddressNumberVisibility = desiredDiamondAddressNumberVisibility
    }
    
    /// Update buildings source with new GeoJSON data (polygon-only or empty to avoid FillBucket LineString errors).
    /// When `data` is nil, clears the source with an empty FeatureCollection.
    /// Always updates the source when map is available so switching display mode shows correct data.
    func updateBuildings(_ data: Data?) {
        guard let mapView = mapView else { return }
        let debugStartedAt = Date()
        
        let dataToUse: Data
        if let data = data {
            dataToUse = data
        } else {
            dataToUse = Self.encodedEmptyBuildings()
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let collection = try decoder.decode(BuildingFeatureCollection.self, from: dataToUse)
            let polygonOnly = collection.features.filter { f in
                f.geometry.type == "Polygon" || f.geometry.type == "MultiPolygon"
            }
            let filtered = BuildingFeatureCollection(type: "FeatureCollection", features: polygonOnly)
            let filteredData = try JSONEncoder().encode(filtered)
            let signature = Self.sourceSignature(for: filteredData)
            guard lastBuildingsSourceSignature != signature else { return }
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: filteredData)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.buildingsSourceId, geoJSON: geoJSON)
            lastBuildingsSourceSignature = signature
            replayCachedBuildingFeatureStates(reason: "geojson_buildings_update")
            if polygonOnly.count < collection.features.count {
                print("✅ [MapLayer] Updated buildings source (\(polygonOnly.count) polygons, filtered \(collection.features.count - polygonOnly.count) non-polygons)")
            } else {
                print("✅ [MapLayer] Updated buildings source (\(polygonOnly.count) features)")
            }
            print("🧪 [MAP_DEBUG] geojson_building_source_updated ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) polygons=\(polygonOnly.count) inputFeatures=\(collection.features.count) role=state_overlay_or_fallback")
        } catch {
            print("❌ [MapLayer] Error updating buildings: \(error)")
            print("🧪 [MAP_DEBUG] geojson_building_source_failed ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(error.localizedDescription)")
        }
    }
    
    private static func encodedEmptyBuildings() -> Data {
        (try? JSONEncoder().encode(BuildingFeatureCollection(type: "FeatureCollection", features: []))) ?? Data()
    }

    private static func sourceSignature(for data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data)
        return hasher.finalize()
    }

    private static func stableJSONData(withJSONObject object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func updateTownhomeStatusOverlay(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]],
        addressStatuses: [UUID: AddressStatus],
        addressStatusRows: [UUID: AddressStatusRow] = [:],
        currentUserId: UUID? = nil
    ) {
        guard let mapView = mapView else { return }

        let data = Self.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding,
            addressStatuses: addressStatuses,
            addressStatusRows: addressStatusRows,
            currentUserId: currentUserId
        ) ?? Self.encodedEmptyTownhomeOverlay()
#if DEBUG
        logTownhomeOverlayUnitChanges(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
        )
#endif
        let signature = Self.sourceSignature(for: data)
        guard lastTownhomeOverlaySignature != signature else { return }

        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.townhomeOverlaySourceId, geoJSON: geoJSON)
            lastTownhomeOverlaySignature = signature
            townhomeOverlayFeatureIdsByBuildingIdentifier = Self.townhomeOverlayFeatureIdsByBuildingIdentifier(from: data)
            let overlayCount = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["features"] as? [[String: Any]] }?
                .count ?? 0
            print("✅ [MapLayer] Updated townhouse overlay source (\(overlayCount) features)")
            replayTownhomeOverlaySelectionStates(reason: "townhome_overlay_update")
        } catch {
            print("❌ [MapLayer] Error updating townhouse overlay: \(error)")
        }
    }

    private static func townhomeOverlayFeatureIdsByBuildingIdentifier(from data: Data) -> [String: Set<String>] {
        guard let collection = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = collection["features"] as? [[String: Any]] else {
            return [:]
        }

        var result: [String: Set<String>] = [:]
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let geometryType = normalizedStringValue(geometry["type"]),
                  geometryType == "polygon" || geometryType == "multipolygon",
                  let featureId = normalizedStringValue(feature["id"]) ?? normalizedStringValue(properties["address_id"]) else {
                continue
            }

            let buildingIdentifiers = Set(
                normalizedStringValues(properties["building_identifiers"])
                    + [normalizedStringValue(properties["gers_id"])].compactMap { $0 }
            )
            for buildingId in buildingIdentifiers {
                result[buildingId, default: []].insert(featureId)
            }
        }
        return result
    }

    private static func normalizedStringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        case let number as NSNumber:
            let normalized = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        case let int as Int:
            return String(int)
        case let double as Double where double.isFinite:
            return double.rounded() == double ? String(Int(double)) : String(double)
        default:
            return nil
        }
    }

    private static func normalizedStringValues(_ value: Any?) -> [String] {
        if let values = value as? [Any] {
            return values.compactMap(normalizedStringValue)
        }
        return normalizedStringValue(value).map { [$0] } ?? []
    }

#if DEBUG
    private func logTownhomeOverlayUnitChanges(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) {
        let audits = Self.townhomeOverlayAuditCounts(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
        )
        var nextCounts: [String: Int] = [:]
        var changedAudits: [TownhomeOverlayAudit] = []
        for audit in audits {
            nextCounts[audit.buildingId] = audit.renderedSliceCount
            guard lastTownhomeOverlayRenderedUnitCounts[audit.buildingId] != audit.renderedSliceCount else {
                continue
            }
            changedAudits.append(audit)
        }
        if !changedAudits.isEmpty {
            let sample = changedAudits.prefix(5).map {
                "\($0.buildingId):\($0.linkedCount)->\($0.renderedSliceCount)"
            }.joined(separator: ",")
            print(
                "🧪 [MapLayer] townhome_overlay_units_changed count=\(changedAudits.count) " +
                "sample=\(sample)"
            )
        }
        lastTownhomeOverlayRenderedUnitCounts = nextCounts
    }
#endif

    private static func encodedEmptyTownhomeOverlay() -> Data {
        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": [] as [[String: Any]]
        ]
        return (try? stableJSONData(withJSONObject: collection)) ?? Data()
    }

    static func buildTownhomeStatusOverlayGeoJSON(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]],
        addressStatuses: [UUID: AddressStatus],
        addressStatusRows: [UUID: AddressStatusRow] = [:],
        currentUserId: UUID? = nil
    ) -> Data? {
        let addressContextsById = overlayAddressContextsById(addresses)

        var featureDictionaries: [[String: Any]] = []

        for building in buildings {
            let gersId = (building.properties.canonicalBuildingIdentifier ?? building.id ?? "").lowercased()
            guard !gersId.isEmpty else { continue }
            let buildingIdentifiers = normalizedBuildingIdentifiers(for: building)

            let addressResolution = orderedAddressResolutionForTownhome(
                buildingIdentifiers: buildingIdentifiers,
                embeddedAddressIds: building.properties.addressUUIDs,
                fallbackAddressId: building.properties.addressId,
                addressesById: addressContextsById,
                orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
            )
            let linkedAddresses = addressResolution.addresses

            guard shouldRenderTownhomeOverlay(for: linkedAddresses) else { continue }

            let polygons = polygonRings(from: building.geometry)
            guard !polygons.isEmpty else { continue }

            let height = max(
                building.properties.heightM ?? building.properties.height,
                Self.defaultBuildingExtrusionHeight
            )
            let base = max(0, min(building.properties.minHeight, height - 0.01))
            let overlayBase = height + Self.townhomeOverlayHeightLift
            let overlayHeight = overlayBase + Self.townhomeOverlayPlateThickness
            let dividerHeight = overlayHeight + Self.townhomeDividerLineLift

            for (index, address) in linkedAddresses.enumerated() {
                let startFraction = Double(index) / Double(linkedAddresses.count)
                let endFraction = Double(index + 1) / Double(linkedAddresses.count)

                guard let clippedPolygons = slicedPolygons(
                    polygons: polygons,
                    startFraction: startFraction,
                    endFraction: endFraction
                ), !clippedPolygons.isEmpty else {
                    continue
                }
                let displayPolygons = clippedPolygons.map {
                    insetPolygonRing($0, insetMeters: 0.38) ?? $0
                }

                let properties: [String: Any] = [
                    "gers_id": gersId,
                    "building_identifiers": buildingIdentifiers,
                    "address_id": address.id.uuidString.lowercased(),
                    "unit_index": index,
                    "unit_count": linkedAddresses.count,
                    "segment_status": overlaySegmentStatus(for: addressStatuses[address.id]),
                    "visit_owner": overlayVisitOwner(for: addressStatusRows[address.id], currentUserId: currentUserId),
                    "height": height,
                    "height_m": height,
                    "min_height": base,
                    "overlay_height": overlayHeight,
                    "overlay_base": overlayBase
                ]

                var feature: [String: Any] = [
                    "type": "Feature",
                    "properties": properties,
                    "id": address.id.uuidString.lowercased()
                ]
                if displayPolygons.count == 1 {
                    feature["geometry"] = [
                        "type": "Polygon",
                        "coordinates": [displayPolygons[0]]
                    ]
                } else {
                    feature["geometry"] = [
                        "type": "MultiPolygon",
                        "coordinates": displayPolygons.map { [$0] }
                    ]
                }
                featureDictionaries.append(feature)
            }

            let dividerLines = townhomeDividerLineStrings(
                polygons: polygons,
                unitCount: linkedAddresses.count
            )
            for (dividerIndex, line) in dividerLines.enumerated() {
                guard line.count >= 2 else { continue }
                featureDictionaries.append([
                    "type": "Feature",
                    "id": "\(gersId)-divider-\(dividerIndex)",
                    "properties": [
                        "gers_id": gersId,
                        "feature_kind": "divider",
                        "unit_count": linkedAddresses.count,
                        "height": height,
                        "height_m": height,
                        "min_height": base,
                        "overlay_height": dividerHeight,
                        "overlay_base": overlayBase
                    ],
                    "geometry": [
                        "type": "LineString",
                        "coordinates": line
                    ]
                ])

            }
        }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": featureDictionaries
        ]
        return try? stableJSONData(withJSONObject: collection)
    }
    
    /// Update addresses source: convert Point features to circle-polygon features (fill extrusions) then update source
    func updateAddressNumberLabels(
        addresses: [AddressFeature],
        buildings: [BuildingFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) {
        guard let mapView = mapView else { return }

        do {
            let labelPointData = try Self.smartAddressLabelPointCollection(
                addresses: addresses,
                buildings: buildings,
                orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
            )
            let labelSignature = Self.sourceSignature(for: labelPointData)
            guard lastAddressNumbersSourceSignature != labelSignature else { return }
            let labelGeoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: labelPointData)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.addressNumbersSourceId, geoJSON: labelGeoJSON)
            lastAddressNumbersSourceSignature = labelSignature
        } catch {
            print("❌ [MapLayer] Error updating address number labels: \(error)")
        }
    }

    func updateAddresses(
        _ data: Data,
        addresses: [AddressFeature] = [],
        buildings: [BuildingFeature] = [],
        orderedAddressIdsByBuilding: [String: [UUID]] = [:]
    ) {
        guard let mapView = mapView else { return }
        
        do {
            let pointData: Data
            if !addresses.isEmpty, !buildings.isEmpty {
                pointData = try Self.smartAddressMarkerPointCollection(
                    addresses: addresses,
                    buildings: buildings,
                    orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
                )
            } else {
                pointData = data
            }

            let pointSignature = Self.sourceSignature(for: pointData)
            let pointCount = (try? JSONSerialization.jsonObject(with: pointData) as? [String: Any]).flatMap { $0["features"] as? [[String: Any]] }?.count ?? 0
            let polygonData: Data
            if cachedAddressPointSignature == pointSignature, let cachedAddressPolygonData {
                polygonData = cachedAddressPolygonData
            } else {
                polygonData = try Self.convertAddressPointsToCirclePolygons(
                    pointData,
                    radiusMeters: 2.0,
                    height: Self.addressMarkerExtrusionHeight,
                    segments: 12
                )
                cachedAddressPointSignature = pointSignature
                cachedAddressPolygonData = polygonData
            }
            let polygonSignature = Self.sourceSignature(for: polygonData)
            guard lastAddressesSourceSignature != polygonSignature else { return }
            let polygonCount = (try? JSONSerialization.jsonObject(with: polygonData) as? [String: Any]).flatMap { $0["features"] as? [[String: Any]] }?.count ?? 0
            print("🔍 [MapLayer] Address circles: \(pointCount) points → \(polygonCount) extrusion polygons")
            if polygonCount == 0, pointCount > 0 {
                print("⚠️ [MapLayer] No circle polygons produced; check Point geometry in address GeoJSON")
            }
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: polygonData)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.addressesSourceId, geoJSON: geoJSON)
            applyAddressExtrusionVisibilityIfNeeded()
            lastAddressesSourceSignature = polygonSignature
            replayCachedAddressFeatureStates(reason: "geojson_addresses_update")
            if polygonCount > 0 {
                print("✅ [MapLayer] Updated addresses source (\(Self.addressesSourceId)) features=\(polygonCount) (layer minZoom=\(Self.addressMarkersLayerMinZoom))")
            } else {
                print("✅ [MapLayer] Updated addresses source (\(Self.addressesSourceId)) features=0")
            }
        } catch {
            print("❌ [MapLayer] Error updating addresses: \(error)")
        }
    }

    private func applyAddressExtrusionVisibilityIfNeeded() {
        guard let mapView = mapView else { return }
        let visibility: Visibility = includeAddressesLayer ? .visible : .none

        if mapView.mapboxMap.layerExists(withId: Self.addressesLayerId) {
            try? mapView.mapboxMap.updateLayer(withId: Self.addressesLayerId, type: FillExtrusionLayer.self) {
                $0.visibility = .constant(visibility)
            }
        }

        if mapView.mapboxMap.layerExists(withId: Self.selectedAddressesLayerId) {
            try? mapView.mapboxMap.updateLayer(withId: Self.selectedAddressesLayerId, type: FillExtrusionLayer.self) {
                $0.visibility = .constant(visibility)
            }
        }
    }

    /// Kept for older call sites, but intentionally no-ops now.
    /// Flattening extrusions during pitch/rotate made buildings appear to shrink.
    func setInteractionQualityMode(_ active: Bool) {
        isInteractionQualityModeActive = false
    }

    private func updateBuildingInteractionQuality(
        _ active: Bool,
        layerId: String,
        heightExpression: Exp,
        baseExpression: Exp,
        on map: MapboxMap
    ) {
        guard map.layerExists(withId: layerId) else { return }
        try? map.updateLayer(withId: layerId, type: FillExtrusionLayer.self) { layer in
            layer.fillExtrusionHeight = active
                ? .constant(Self.interactionBuildingExtrusionHeight)
                : .expression(heightExpression)
            layer.fillExtrusionBase = active
                ? .constant(0)
                : .expression(baseExpression)
            layer.fillExtrusionHeightTransition = StyleTransition(duration: active ? 0 : 0.14, delay: 0)
        }
    }

    private func updateAddressInteractionQuality(_ active: Bool, layerId: String, on map: MapboxMap) {
        guard map.layerExists(withId: layerId) else { return }
        try? map.updateLayer(withId: layerId, type: FillExtrusionLayer.self) { layer in
            layer.fillExtrusionHeight = active
                ? .constant(Self.interactionAddressExtrusionHeight)
                : .expression(Self.addressMarkerExtrusionHeightExpression)
            layer.fillExtrusionBase = active
                ? .constant(0)
                : .expression(Self.addressMarkerExtrusionBaseExpression)
            layer.fillExtrusionHeightTransition = StyleTransition(duration: active ? 0 : 0.14, delay: 0)
        }
    }

    func updateManualAddressPreview(coordinate: CLLocationCoordinate2D?) {
        guard let mapView = mapView else { return }
        guard mapView.mapboxMap.sourceExists(withId: Self.manualAddressPreviewSourceId) else { return }

        let geoJSON: GeoJSONObject
        if let coordinate {
            do {
                let pointData = try Self.pointFeatureCollectionData(
                    coordinate: coordinate,
                    id: "manual-address-preview",
                    properties: [
                        "id": "manual-address-preview",
                        "height": Self.addressMarkerExtrusionHeight
                    ]
                )
                let polygonData = try Self.convertAddressPointsToCirclePolygons(
                    pointData,
                    radiusMeters: 2.0,
                    height: Self.addressMarkerExtrusionHeight,
                    segments: 36
                )
                geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: polygonData)
            } catch {
                print("❌ [MapLayer] Error updating manual address preview: \(error)")
                return
            }
        } else {
            geoJSON = .featureCollection(FeatureCollection(features: []))
        }

        mapView.mapboxMap.updateGeoJSONSource(
            withId: Self.manualAddressPreviewSourceId,
            geoJSON: geoJSON
        )
    }

    func clearManualAddressPreview() {
        updateManualAddressPreview(coordinate: nil)
    }

    func updateTeammatePresence(_ teammates: [SharedCanvassingTeammate]) {
        guard let mapView = mapView else { return }
        guard mapView.mapboxMap.sourceExists(withId: Self.teammatePresenceSourceId) else { return }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": teammates.map { teammate in
                [
                    "type": "Feature",
                    "id": teammate.userId.uuidString.lowercased(),
                    "geometry": [
                        "type": "Point",
                        "coordinates": [teammate.longitude, teammate.latitude]
                    ],
                    "properties": [
                        "initials": teammate.initials,
                        "freshness": teammate.freshness == .stale ? "stale" : "live",
                        "presence_status": teammate.presenceStatus.rawValue,
                        "opacity": teammate.opacity
                    ]
                ]
            }
        ]

        guard let data = try? Self.stableJSONData(withJSONObject: collection) else { return }
        let signature = Self.sourceSignature(for: data)
        guard lastTeammatePresenceSignature != signature else { return }

        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.teammatePresenceSourceId, geoJSON: geoJSON)
            lastTeammatePresenceSignature = signature
        } catch {
            print("❌ [MapLayer] Error updating teammate presence: \(error)")
        }
    }

    func updateAddressNumberLabelVisibility(isVisible: Bool) {
        guard let mapView = mapView else { return }
        guard lastAddressNumbersVisible != isVisible else { return }
        guard mapView.mapboxMap.layerExists(withId: Self.addressNumbersLayerId) else { return }

        do {
            try mapView.mapboxMap.updateLayer(withId: Self.addressNumbersLayerId, type: SymbolLayer.self) {
                $0.visibility = .constant(isVisible ? .visible : .none)
            }
            if mapView.mapboxMap.layerExists(withId: Self.addressLabelHitboxLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.addressLabelHitboxLayerId, type: CircleLayer.self) {
                    $0.visibility = .constant(isVisible ? .visible : .none)
                }
            }
            lastAddressNumbersVisible = isVisible
        } catch {
            print("❌ [MapLayer] Error updating address number label visibility: \(error)")
        }
    }

    func updateAddressHouseIconVisibility(isVisible: Bool) {
        guard let mapView = mapView else { return }
        guard mapView.mapboxMap.layerExists(withId: Self.addressHouseIconLayerId) else { return }

        do {
            try mapView.mapboxMap.updateLayer(withId: Self.addressHouseIconLayerId, type: SymbolLayer.self) {
                $0.visibility = .constant(isVisible ? .visible : .none)
            }
        } catch {
            print("❌ [MapLayer] Error updating address house emblem visibility: \(error)")
        }
    }

    /// Address mode intentionally keeps addresses and parcels visible across the full camera range.
    /// Building mode restores the normal zoom ramps so the standard map remains uncluttered.
    func updateAddressModeZoomVisibility(isAddressMode: Bool) {
        desiredAddressModeZoomVisibility = isAddressMode
        guard let mapView = mapView else { return }
        guard let map = mapView.mapboxMap else { return }
        let addressMinZoom = isAddressMode ? Self.addressModeMinimumZoom : Self.addressMarkersLayerMinZoom
        let addressLabelMinZoom = Self.addressNumbersLayerMinZoom
        let parcelMinZoom = isAddressMode ? Self.addressModeMinimumZoom : Self.parcelsOverviewMinZoom
        let parcelMaxZoom = isAddressMode ? Self.addressModeMaximumZoom : Self.parcelsOverviewMaxZoom

        if map.layerExists(withId: Self.addressesLayerId) {
            try? map.updateLayer(withId: Self.addressesLayerId, type: FillExtrusionLayer.self) {
                $0.minZoom = addressMinZoom
                $0.fillExtrusionOpacity = isAddressMode
                    ? .constant(1.0)
                    : .expression(Self.addressMarkersZoomOpacityExpression)
            }
        }

        if map.layerExists(withId: Self.selectedAddressesLayerId) {
            try? map.updateLayer(withId: Self.selectedAddressesLayerId, type: FillExtrusionLayer.self) {
                $0.minZoom = addressMinZoom
            }
        }

        if map.layerExists(withId: Self.addressNumbersLayerId) {
            try? map.updateLayer(withId: Self.addressNumbersLayerId, type: SymbolLayer.self) {
                $0.minZoom = addressLabelMinZoom
                $0.textOpacity = .expression(Self.addressNumbersZoomOpacityExpression)
            }
        }

        if map.layerExists(withId: Self.addressLabelHitboxLayerId) {
            try? map.updateLayer(withId: Self.addressLabelHitboxLayerId, type: CircleLayer.self) {
                $0.minZoom = addressLabelMinZoom
            }
        }

        if map.layerExists(withId: Self.addressHouseIconLayerId) {
            try? map.updateLayer(withId: Self.addressHouseIconLayerId, type: SymbolLayer.self) {
                $0.minZoom = addressMinZoom
                $0.maxZoom = isAddressMode ? Self.addressModeMaximumZoom : 15.4
                $0.iconOpacity = isAddressMode
                    ? .constant(1.0)
                    : .expression(Self.addressHouseIconsZoomOpacityExpression)
            }
        }

        if map.layerExists(withId: Self.parcelsFillLayerId) {
            try? map.updateLayer(withId: Self.parcelsFillLayerId, type: FillLayer.self) {
                $0.minZoom = parcelMinZoom
                $0.maxZoom = parcelMaxZoom
                $0.fillOpacity = isAddressMode
                    ? .constant(0.14)
                    : .expression(Self.parcelOverviewFillOpacityExpression)
            }
        }

        if map.layerExists(withId: Self.parcelsLineLayerId) {
            try? map.updateLayer(withId: Self.parcelsLineLayerId, type: LineLayer.self) {
                $0.minZoom = parcelMinZoom
                $0.maxZoom = parcelMaxZoom
                $0.lineOpacity = isAddressMode
                    ? .constant(0.72)
                    : .expression(Self.parcelOverviewLineOpacityExpression)
                $0.lineWidth = .expression(
                    isAddressMode
                        ? Self.addressModeParcelLineWidthExpression
                        : Self.parcelOverviewLineWidthExpression
                )
            }
        }

        updateDiamondAddressModeZoomVisibility(isAddressMode: isAddressMode)
    }

    private func updateDiamondAddressModeZoomVisibility(isAddressMode: Bool) {
        guard let mapView = mapView else { return }
        guard let map = mapView.mapboxMap else { return }
        let addressMinZoom = isAddressMode
            ? Self.addressModeMinimumZoom
            : VectorTileDiamondGeometryProvider.addressLayerMinZoom
        let addressLabelMinZoom = VectorTileDiamondGeometryProvider.addressNumberLayerMinZoom
        let parcelMinZoom = isAddressMode
            ? Self.addressModeMinimumZoom
            : VectorTileDiamondGeometryProvider.parcelOverviewMinZoom
        let parcelMaxZoom = isAddressMode
            ? Self.addressModeMaximumZoom
            : VectorTileDiamondGeometryProvider.parcelOverviewMaxZoom

        if map.layerExists(withId: VectorTileDiamondGeometryProvider.addressCircleLayerId) {
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.addressCircleLayerId, type: FillExtrusionLayer.self) {
                $0.minZoom = addressMinZoom
            }
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.addressCircleLayerId, type: CircleLayer.self) {
                $0.minZoom = addressMinZoom
            }
        }

        if map.layerExists(withId: VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId) {
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId, type: FillExtrusionLayer.self) {
                $0.minZoom = addressMinZoom
            }
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId, type: CircleLayer.self) {
                $0.minZoom = addressMinZoom
            }
        }

        if map.layerExists(withId: VectorTileDiamondGeometryProvider.addressNumberLayerId) {
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.addressNumberLayerId, type: SymbolLayer.self) {
                $0.minZoom = addressLabelMinZoom
                $0.textOpacity = .expression(
                    VectorTileDiamondGeometryProvider.linkedAddressNumberOpacityExpression(
                        linkedExpression: VectorTileDiamondGeometryProvider.linkedAddressNumberExpression,
                        isAddressMode: isAddressMode
                    )
                )
            }
        }

        if map.layerExists(withId: VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId) {
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.buildingAddressNumberLayerId, type: SymbolLayer.self) {
                $0.minZoom = addressLabelMinZoom
                $0.textOpacity = .expression(
                    VectorTileDiamondGeometryProvider.linkedAddressNumberOpacityExpression(
                        linkedExpression: VectorTileDiamondGeometryProvider.linkedBuildingNumberExpression,
                        isAddressMode: isAddressMode
                    )
                )
            }
        }

        if map.layerExists(withId: VectorTileDiamondGeometryProvider.parcelFillLayerId) {
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.parcelFillLayerId, type: FillLayer.self) {
                $0.minZoom = parcelMinZoom
                $0.maxZoom = parcelMaxZoom
                $0.fillOpacity = isAddressMode
                    ? .constant(0.14)
                    : .expression(Self.diamondParcelOverviewFillOpacityExpression)
            }
        }

        if map.layerExists(withId: VectorTileDiamondGeometryProvider.parcelLineLayerId) {
            try? map.updateLayer(withId: VectorTileDiamondGeometryProvider.parcelLineLayerId, type: LineLayer.self) {
                $0.minZoom = parcelMinZoom
                $0.maxZoom = parcelMaxZoom
                $0.lineOpacity = isAddressMode
                    ? .constant(0.72)
                    : .expression(Self.diamondParcelLineOpacityExpression)
            }
        }
    }
    
    /// Extract centroid [lon, lat] from Polygon or MultiPolygon geometry coordinates (handles NSArray/NSNumber from JSONSerialization).
    private static func centroidFromGeometryCoordinates(_ coordsAny: Any?, geomType: String) -> [Double]? {
        guard let coordsAny = coordsAny else { return nil }
        let ring: [[Double]]?
        if geomType == "Polygon" {
            ring = firstRingFromPolygonCoords(coordsAny)
        } else if geomType == "MultiPolygon" {
            ring = firstRingFromMultiPolygonCoords(coordsAny)
        } else {
            return nil
        }
        guard let firstRing = ring, !firstRing.isEmpty else { return nil }
        var sumLon = 0.0, sumLat = 0.0
        for pt in firstRing {
            if pt.count >= 2 {
                sumLon += pt[0]
                sumLat += pt[1]
            }
        }
        let n = Double(firstRing.count)
        return [sumLon / n, sumLat / n]
    }
    
    private static func firstRingFromPolygonCoords(_ any: Any) -> [[Double]]? {
        guard let arr = any as? [Any], let first = arr.first else { return nil }
        return arrayOfDoublePairs(from: first)
    }
    
    private static func firstRingFromMultiPolygonCoords(_ any: Any) -> [[Double]]? {
        guard let polys = any as? [Any], let firstPoly = polys.first else { return nil }
        return firstRingFromPolygonCoords(firstPoly)
    }
    
    private static func arrayOfDoublePairs(from any: Any) -> [[Double]]? {
        guard let arr = any as? [Any] else { return nil }
        var out: [[Double]] = []
        for item in arr {
            if let pair = doublePair(from: item) { out.append(pair) }
        }
        return out.isEmpty ? nil : out
    }
    
    private static func doublePair(from any: Any) -> [Double]? {
        guard let arr = any as? [Any], arr.count >= 2 else { return nil }
        let a = numberToDouble(arr[0])
        let b = numberToDouble(arr[1])
        guard let x = a, let y = b else { return nil }
        return [x, y]
    }
    
    private static func numberToDouble(_ any: Any) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let i = any as? Int { return Double(i) }
        return nil
    }
    
    /// Extract [lon, lat] from Point geometry coordinates (handles NSArray/NSNumber from JSONSerialization).
    private static func pointCoordinatesFromAny(_ any: Any) -> [Double]? {
        guard let arr = any as? [Any], arr.count >= 2,
              let lon = numberToDouble(arr[0]), let lat = numberToDouble(arr[1]) else { return nil }
        return [lon, lat]
    }
    
    /// Build a Point FeatureCollection from building polygon centroids (fallback when campaign has no address points).
    /// Circle extrusions can then be drawn at each building center.
    private static func pointFeatureCollectionFromBuildingCentroids(_ buildingGeoJSONData: Data) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: buildingGeoJSONData) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return try stableJSONData(withJSONObject: ["type": "FeatureCollection", "features": [] as [[String: Any]]])
        }
        var pointFeatures: [[String: Any]] = []
        for feature in features {
            guard let geom = feature["geometry"] as? [String: Any],
                  let geomType = geom["type"] as? String else { continue }
            guard let coords = centroidFromGeometryCoordinates(geom["coordinates"], geomType: geomType),
                  coords[0].isFinite, coords[1].isFinite, abs(coords[1]) < 89 else { continue }
            var props = (feature["properties"] as? [String: Any]) ?? [:]
            // Prefer address_id so setFeatureState(addressId) matches; fall back to building_id/gers_id/id.
            var idStr: String?
            if let s = props["address_id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = props["building_id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = props["gers_id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = props["id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = feature["id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let idInt = feature["id"] as? Int { idStr = String(idInt) }
            if idStr == nil, let idNum = feature["id"] as? NSNumber { idStr = idNum.stringValue }
            if let id = idStr { props["id"] = id.contains("-") ? id.lowercased() : id }
            var pointFeature: [String: Any] = [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": coords],
                "properties": props
            ]
            if let id = idStr { pointFeature["id"] = id }
            pointFeatures.append(pointFeature)
        }
        let collection: [String: Any] = ["type": "FeatureCollection", "features": pointFeatures]
        return try stableJSONData(withJSONObject: collection)
    }

    private static func pointFeatureCollectionData(
        coordinate: CLLocationCoordinate2D,
        id: String,
        properties: [String: Any]
    ) throws -> Data {
        let feature: [String: Any] = [
            "type": "Feature",
            "id": id,
            "geometry": [
                "type": "Point",
                "coordinates": [coordinate.longitude, coordinate.latitude]
            ],
            "properties": properties
        ]
        return try JSONSerialization.data(
            withJSONObject: [
                "type": "FeatureCollection",
                "features": [feature]
            ]
        )
    }

    private static func smartAddressLabelPointCollection(
        addresses: [AddressFeature],
        buildings: [BuildingFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) throws -> Data {
        let buildingContexts = labelBuildingContexts(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding,
            includeAddressFeatureLinks: false
        )

        var buildingByIdentifier: [String: LabelBuildingContext] = [:]
        var buildingByAddressId: [UUID: LabelBuildingContext] = [:]
        for context in buildingContexts {
            for identifier in context.identifiers {
                buildingByIdentifier[identifier] = context
            }
            for addressId in context.orderedAddressIds {
                buildingByAddressId[addressId] = context
            }
        }

        let addressPointFeatures = smartAddressPointFeatures(
            addresses: addresses,
            buildingContexts: buildingContexts,
            buildingByIdentifier: buildingByIdentifier,
            buildingByAddressId: buildingByAddressId,
            requireHouseNumberLabel: true,
            requireCurrentBuildingLink: true,
            keepSingleAddressCoordinate: true
        )

        let existingAddressFeatureIds = Set(addressPointFeatures.compactMap { feature -> String? in
            guard let id = feature["id"] as? String else { return nil }
            return id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        let existingBuildingIdentifiers = Set(addressPointFeatures.flatMap { feature -> [String] in
            guard let properties = feature["properties"] as? [String: Any] else { return [] }
            if let identifiers = properties["linked_building_identifiers"] as? [String] {
                return identifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            }
            return [
                properties["building_gers_id"],
                properties["public_building_id"],
                properties["canonical_building_id"]
            ]
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        })
        let buildingFallbackFeatures = buildingAddressLabelPointFeatures(
            buildings: buildings,
            buildingByIdentifier: buildingByIdentifier,
            existingFeatureIds: existingAddressFeatureIds,
            existingBuildingIdentifiers: existingBuildingIdentifiers
        )

        return try stableJSONData(withJSONObject: [
            "type": "FeatureCollection",
            "features": addressPointFeatures + buildingFallbackFeatures
        ])
    }

    static func buildAddressNumberLabelPointGeoJSON(
        addresses: [AddressFeature],
        buildings: [BuildingFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) throws -> Data {
        try smartAddressLabelPointCollection(
            addresses: addresses,
            buildings: buildings,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
        )
    }

    private static func smartAddressMarkerPointCollection(
        addresses: [AddressFeature],
        buildings: [BuildingFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) throws -> Data {
        let buildingContexts = labelBuildingContexts(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
        )

        var buildingByIdentifier: [String: LabelBuildingContext] = [:]
        var buildingByAddressId: [UUID: LabelBuildingContext] = [:]
        for context in buildingContexts {
            for identifier in context.identifiers {
                buildingByIdentifier[identifier] = context
            }
            for addressId in context.orderedAddressIds {
                buildingByAddressId[addressId] = context
            }
        }

        let pointFeatures = smartAddressPointFeatures(
            addresses: addresses,
            buildingContexts: buildingContexts,
            buildingByIdentifier: buildingByIdentifier,
            buildingByAddressId: buildingByAddressId,
            requireHouseNumberLabel: false,
            requireCurrentBuildingLink: false,
            keepSingleAddressCoordinate: true
        )

        return try stableJSONData(withJSONObject: [
            "type": "FeatureCollection",
            "features": pointFeatures
        ])
    }

    private static func smartAddressPointFeatures(
        addresses: [AddressFeature],
        buildingContexts: [LabelBuildingContext],
        buildingByIdentifier: [String: LabelBuildingContext],
        buildingByAddressId: [UUID: LabelBuildingContext],
        requireHouseNumberLabel: Bool,
        requireCurrentBuildingLink: Bool,
        keepSingleAddressCoordinate: Bool
    ) -> [[String: Any]] {
        addresses.compactMap { feature in
            let featureProperties: [String: Any] = [
                "id": feature.properties.id as Any,
                "address_id": feature.properties.id as Any,
                "house_number": feature.properties.houseNumber as Any,
                "street_name": feature.properties.streetName as Any,
                "formatted": feature.properties.formatted as Any,
                "gers_id": feature.properties.gersId as Any,
                "building_gers_id": feature.properties.buildingGersId as Any,
                "public_building_id": (feature.properties.buildingGersId ?? feature.properties.gersId) as Any,
                "canonical_building_id": (feature.properties.buildingGersId ?? feature.properties.gersId) as Any,
                "source": feature.properties.source as Any
            ]

            guard let addressIdString = normalizedFeatureIdentifier(
                feature: ["id": feature.id as Any],
                properties: featureProperties
            ) else {
                return nil
            }

            let houseLabel = normalizedHouseNumberLabel(from: featureProperties)
            guard !requireHouseNumberLabel || !houseLabel.isEmpty else { return nil }
            guard let baseCoordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else { return nil }

            let addressUUID = UUID(uuidString: addressIdString)
            let buildingIdentifiers = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let linkedBuildingByIdentifier = buildingIdentifiers.compactMap { buildingByIdentifier[$0] }.first { context in
                guard context.usesExplicitAddressIds, let addressUUID else { return true }
                return context.orderedAddressIds.contains(addressUUID)
            }
            let containingBuilding = buildingContext(containing: baseCoordinate, in: buildingContexts).flatMap { context -> LabelBuildingContext? in
                guard context.usesExplicitAddressIds else { return context }
                guard let addressUUID else { return nil }
                return context.orderedAddressIds.contains(addressUUID) ? context : nil
            }

            let explicitlyLinkedBuilding = addressUUID.flatMap { buildingByAddressId[$0] }
            let linkedBuilding = requireCurrentBuildingLink
                ? explicitlyLinkedBuilding
                : explicitlyLinkedBuilding ?? linkedBuildingByIdentifier ?? containingBuilding
            guard !requireCurrentBuildingLink || linkedBuilding != nil else { return nil }

            let resolvedCoordinate: CLLocationCoordinate2D
            let labelPriority: Double
            var labelZOffset = Self.addressMarkerExtrusionHeight + Self.addressNumberRoofClearance

            if let linkedBuilding {
                let totalAddresses = linkedAddressCount(for: linkedBuilding)
                let addressIndex = addressUUID.flatMap { uuid in
                    linkedBuilding.orderedAddressIds.firstIndex(of: uuid)
                } ?? 0
                if keepSingleAddressCoordinate {
                    resolvedCoordinate = baseCoordinate
                } else {
                    resolvedCoordinate = preferredLabelCoordinate(
                        building: linkedBuilding,
                        addressIndex: addressIndex,
                        totalAddresses: totalAddresses
                    )
                }
                labelPriority = labelPriorityValue(
                    building: linkedBuilding,
                    totalAddresses: totalAddresses,
                    addressIndex: addressIndex
                )
                if !keepSingleAddressCoordinate {
                    labelZOffset = linkedBuilding.height + Self.addressNumberRoofClearance
                }
            } else {
                resolvedCoordinate = baseCoordinate
                labelPriority = 90
            }

            let usesBuildingPlacement = linkedBuilding != nil && !keepSingleAddressCoordinate
            var labelProperties: [String: Any] = [
                "id": addressIdString,
                "address_id": addressIdString,
                "label_priority": labelPriority,
                "label_z_offset": labelZOffset,
                "geometry_source": usesBuildingPlacement ? "building" : "address_point",
                "has_building_geometry": linkedBuilding != nil
            ]
            if let linkedBuilding {
                labelProperties["linked_building_identifiers"] = linkedBuilding.identifiers
                if labelProperties["building_gers_id"] == nil,
                   let buildingIdentifier = linkedBuilding.identifiers.first {
                    labelProperties["building_gers_id"] = buildingIdentifier
                }
                if let publicBuildingIdentifier = linkedBuilding.identifiers.first {
                    labelProperties["public_building_id"] = publicBuildingIdentifier
                    labelProperties["canonical_building_id"] = publicBuildingIdentifier
                }
            }
            if !houseLabel.isEmpty { labelProperties["house_number_label"] = houseLabel }
            if let formatted = feature.properties.formatted { labelProperties["formatted"] = formatted }
            if let houseNumber = feature.properties.houseNumber { labelProperties["house_number"] = houseNumber }
            if let streetName = feature.properties.streetName { labelProperties["street_name"] = streetName }
            if let postalCode = feature.properties.postalCode { labelProperties["postal_code"] = postalCode }
            if let locality = feature.properties.locality { labelProperties["locality"] = locality }
            if let gersId = feature.properties.gersId { labelProperties["gers_id"] = gersId }
            if let buildingGersId = feature.properties.buildingGersId { labelProperties["building_gers_id"] = buildingGersId }
            if let source = feature.properties.source { labelProperties["source"] = source }

            return [
                "type": "Feature",
                "id": addressIdString,
                "geometry": [
                    "type": "Point",
                    "coordinates": [resolvedCoordinate.longitude, resolvedCoordinate.latitude]
                ],
                "properties": labelProperties
            ]
        }
    }

    private static func buildingAddressLabelPointFeatures(
        buildings: [BuildingFeature],
        buildingByIdentifier: [String: LabelBuildingContext],
        existingFeatureIds: Set<String>,
        existingBuildingIdentifiers: Set<String>
    ) -> [[String: Any]] {
        buildings.compactMap { building -> [String: Any]? in
            let properties = building.properties
            guard properties.effectiveIsLinked else { return nil }
            let houseLabel = normalizedHouseNumberLabel(from: [
                "house_number": properties.houseNumber as Any,
                "formatted": properties.addressText as Any
            ])
            guard !houseLabel.isEmpty else { return nil }

            let identifiers = properties.buildingIdentifierCandidates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            guard !identifiers.contains(where: existingBuildingIdentifiers.contains) else { return nil }
            let linkedBuilding = identifiers.compactMap { buildingByIdentifier[$0] }.first
            let directAddressId = properties.addressId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawFeatureId = directAddressId.flatMap { $0.isEmpty ? nil : $0 }
                ?? properties.canonicalBuildingIdentifier
                ?? building.id
                ?? properties.id
            let featureId = rawFeatureId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !featureId.isEmpty, !existingFeatureIds.contains(featureId.lowercased()) else { return nil }

            let coordinate: CLLocationCoordinate2D
            let labelPriority: Double
            let labelZOffset: Double
            if let linkedBuilding {
                let totalAddresses = linkedAddressCount(for: linkedBuilding)
                let addressIndex = directAddressId
                    .flatMap(UUID.init(uuidString:))
                    .flatMap { linkedBuilding.orderedAddressIds.firstIndex(of: $0) }
                    ?? 0
                coordinate = preferredLabelCoordinate(
                    building: linkedBuilding,
                    addressIndex: addressIndex,
                    totalAddresses: totalAddresses
                )
                labelPriority = labelPriorityValue(
                    building: linkedBuilding,
                    totalAddresses: totalAddresses,
                    addressIndex: addressIndex
                )
                labelZOffset = linkedBuilding.height + Self.addressNumberRoofClearance
            } else if let centroid = CampaignTargetResolver.coordinate(for: building.geometry) {
                coordinate = centroid
                labelPriority = 80
                labelZOffset = max(
                    properties.heightM ?? properties.height,
                    Self.defaultBuildingExtrusionHeight
                ) + Self.addressNumberRoofClearance
            } else {
                return nil
            }

            let displayAddress = CampaignTargetResolver.displayAddressText(
                formatted: properties.addressText,
                houseNumber: properties.houseNumber,
                streetName: properties.streetName
            )
            var labelProperties: [String: Any] = [
                "id": featureId,
                "house_number_label": houseLabel,
                "label_priority": labelPriority,
                "label_z_offset": labelZOffset,
                "geometry_source": properties.source?.lowercased() == "manual_fallback" ? "manual_fallback" : "building",
                "has_building_geometry": true
            ]
            if let directAddressId, !directAddressId.isEmpty { labelProperties["address_id"] = directAddressId }
            if let displayAddress { labelProperties["formatted"] = displayAddress }
            if let houseNumber = properties.houseNumber { labelProperties["house_number"] = houseNumber }
            if let streetName = properties.streetName { labelProperties["street_name"] = streetName }
            if let gersId = properties.gersId { labelProperties["gers_id"] = gersId }
            if let buildingId = properties.buildingId ?? properties.gersId ?? properties.canonicalBuildingIdentifier {
                labelProperties["building_gers_id"] = buildingId
            }
            if let publicBuildingId = properties.canonicalBuildingIdentifier {
                labelProperties["public_building_id"] = publicBuildingId
                labelProperties["canonical_building_id"] = publicBuildingId
            }
            if let source = properties.source { labelProperties["source"] = source }

            return [
                "type": "Feature",
                "id": featureId,
                "geometry": [
                    "type": "Point",
                    "coordinates": [coordinate.longitude, coordinate.latitude]
                ],
                "properties": labelProperties
            ]
        }
    }

    private static func normalizedFeatureIdentifier(feature: [String: Any], properties: [String: Any]) -> String? {
        let candidates: [Any?] = [
            properties["id"],
            properties["address_id"],
            feature["id"]
        ]

        for candidate in candidates {
            if let string = candidate as? String, !string.isEmpty {
                return string.contains("-") ? string.lowercased() : string
            }
            if let int = candidate as? Int {
                return String(int)
            }
            if let number = candidate as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func normalizedHouseNumberLabel(from properties: [String: Any]) -> String {
        func clean(_ value: Any?) -> String {
            if let string = value as? String {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let number = value as? NSNumber {
                return number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let int = value as? Int {
                return String(int)
            }
            if let double = value as? Double, double.isFinite {
                return double.rounded() == double ? String(Int(double)) : String(double)
            }
            return ""
        }

        func isHouseNumberLabel(_ value: String) -> Bool {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return false }
            let uppercased = normalized.uppercased()
            if uppercased == "UPRN" || uppercased.hasPrefix("UPRN ") || uppercased.hasPrefix("OS-OPEN-UPRN") {
                return false
            }
            return normalized.range(of: #"^\d+[A-Za-z0-9/\-]*$"#, options: .regularExpression) != nil
        }

        for key in ["house_number_label", "house_number", "street_number", "number", "address_number"] {
            let directHouseNumber = clean(properties[key])
            if isHouseNumberLabel(directHouseNumber) {
                return directHouseNumber
            }
        }

        let formatted = clean(properties["formatted"])
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        let firstToken = streetOnly.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return isHouseNumberLabel(firstToken) ? firstToken : ""
    }

    private struct LabelBuildingContext {
        let identifiers: [String]
        let centroid: CLLocationCoordinate2D
        let polygons: [[[Double]]]
        let orderedAddressIds: [UUID]
        let addressCount: Int
        let height: Double
        let usesExplicitAddressIds: Bool
    }

    private static func labelBuildingContexts(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]],
        includeAddressFeatureLinks: Bool = true
    ) -> [LabelBuildingContext] {
        let addressesByIdentifier = Dictionary(grouping: addresses) { feature in
            (feature.properties.buildingGersId ?? feature.properties.gersId ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        return buildings.compactMap { building in
            guard let centroid = CampaignTargetResolver.coordinate(for: building.geometry) else { return nil }
            let polygons = polygonRings(from: building.geometry)

            let identifiers = normalizedBuildingIdentifiers(for: building)
            guard !identifiers.isEmpty else { return nil }

            let explicitAddressIds = explicitlyMappedAddressIds(
                for: identifiers,
                orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
            )

            var orderedAddressIds: [UUID]
            if let explicitAddressIds {
                orderedAddressIds = explicitAddressIds
            } else {
                orderedAddressIds = building.properties.addressUUIDs
                if includeAddressFeatureLinks {
                    for identifier in identifiers {
                        if let featureGroup = addressesByIdentifier[identifier] {
                            orderedAddressIds.append(contentsOf: featureGroup.sorted(by: compareLabelAddresses).compactMap { feature in
                                guard let id = feature.properties.id ?? feature.id else { return nil }
                                return UUID(uuidString: id)
                            })
                        }
                    }
                }

                if let directAddressId = building.properties.addressId.flatMap(UUID.init(uuidString:)) {
                    orderedAddressIds.append(directAddressId)
                }
            }

            orderedAddressIds = dedupePreservingOrder(orderedAddressIds)
            let addressCount = explicitAddressIds != nil
                ? max(orderedAddressIds.count, 1)
                : max(
                    orderedAddressIds.count,
                    building.properties.addressCount ?? 0,
                    building.properties.unitsCount,
                    1
                )

            return LabelBuildingContext(
                identifiers: identifiers,
                centroid: centroid,
                polygons: polygons,
                orderedAddressIds: orderedAddressIds,
                addressCount: addressCount,
                height: max(
                    building.properties.heightM ?? building.properties.height,
                    Self.defaultBuildingExtrusionHeight
                ),
                usesExplicitAddressIds: explicitAddressIds != nil
            )
        }
    }

    private static func compareLabelAddresses(_ lhs: AddressFeature, _ rhs: AddressFeature) -> Bool {
        let lhsHouse = houseNumberSortParts(
            houseNumber: lhs.properties.houseNumber,
            formatted: lhs.properties.formatted
        )
        let rhsHouse = houseNumberSortParts(
            houseNumber: rhs.properties.houseNumber,
            formatted: rhs.properties.formatted
        )

        switch (lhsHouse.number, rhsHouse.number) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if lhsHouse.suffix != rhsHouse.suffix {
            return lhsHouse.suffix.localizedStandardCompare(rhsHouse.suffix) == .orderedAscending
        }

        let lhsFormatted = (lhs.properties.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsFormatted = (rhs.properties.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return lhsFormatted.localizedStandardCompare(rhsFormatted) == .orderedAscending
    }

    private static func preferredLabelCoordinate(
        building: LabelBuildingContext,
        addressIndex: Int,
        totalAddresses: Int
    ) -> CLLocationCoordinate2D {
        guard totalAddresses > 1,
              let coordinate = roofDistributedLabelCoordinate(
                building: building,
                addressIndex: addressIndex,
                totalAddresses: totalAddresses
              ) else {
            return building.centroid
        }
        return coordinate
    }

    private static func buildingContext(
        containing coordinate: CLLocationCoordinate2D,
        in contexts: [LabelBuildingContext]
    ) -> LabelBuildingContext? {
        contexts.first { context in
            context.polygons.contains { ring in
                pointInPolygon(
                    longitude: coordinate.longitude,
                    latitude: coordinate.latitude,
                    ring: ring
                )
            }
        }
    }

    private static func roofDistributedLabelCoordinate(
        building: LabelBuildingContext,
        addressIndex: Int,
        totalAddresses: Int
    ) -> CLLocationCoordinate2D? {
        let clampedIndex = min(max(addressIndex, 0), max(totalAddresses - 1, 0))
        let clampedTotal = max(totalAddresses, 1)
        let startFraction = Double(clampedIndex) / Double(clampedTotal)
        let endFraction = Double(clampedIndex + 1) / Double(clampedTotal)

        guard let addressSlice = slicedPolygons(
            polygons: building.polygons,
            startFraction: startFraction,
            endFraction: endFraction
        ) else {
            return nil
        }

        return centroidCoordinate(for: addressSlice)
    }

    private static func largestPolygonRing(in polygons: [[[Double]]]) -> [[Double]]? {
        polygons
            .filter { $0.count >= 3 }
            .max { abs(polygonSignedArea($0)) < abs(polygonSignedArea($1)) }
    }

    private static func polygonSignedArea(_ ring: [[Double]]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var area = 0.0
        for index in ring.indices {
            let nextIndex = ring.index(after: index) == ring.endIndex ? ring.startIndex : ring.index(after: index)
            area += (ring[index][0] * ring[nextIndex][1]) - (ring[nextIndex][0] * ring[index][1])
        }
        return area / 2.0
    }

    private static func pointInPolygon(longitude: Double, latitude: Double, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }

        var isInside = false
        var previousIndex = ring.count - 1
        for currentIndex in 0..<ring.count {
            let current = ring[currentIndex]
            let previous = ring[previousIndex]
            guard current.count >= 2, previous.count >= 2 else {
                previousIndex = currentIndex
                continue
            }

            let currentLat = current[1]
            let previousLat = previous[1]
            let currentLon = current[0]
            let previousLon = previous[0]
            let crossesLatitude = (currentLat > latitude) != (previousLat > latitude)

            if crossesLatitude {
                let intersectionLon = (previousLon - currentLon) * (latitude - currentLat) / (previousLat - currentLat) + currentLon
                if longitude < intersectionLon {
                    isInside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return isInside
    }

    private static func linkedAddressCount(for building: LabelBuildingContext) -> Int {
        if !building.orderedAddressIds.isEmpty {
            return max(building.orderedAddressIds.count, 1)
        }
        return max(building.addressCount, 1)
    }

    private static func labelPriorityValue(
        building: LabelBuildingContext,
        totalAddresses: Int,
        addressIndex: Int
    ) -> Double {
        let linkedPriority = totalAddresses <= 1 ? 0.0 : 8.0
        let densityPenalty = Double(max(totalAddresses - 1, 0)) * 1.7
        let heightBonus = min(building.height / 24.0, 2.5)
        return linkedPriority + densityPenalty + Double(addressIndex) - heightBonus
    }

    
    /// When campaign has buildings but no address points (e.g. snapshot-only), show circle extrusions at building centroids.
    func updateAddressesFromBuildingCentroids(buildingGeoJSONData: Data?) {
        guard let data = buildingGeoJSONData else {
            print("🔍 [MapLayer] updateAddressesFromBuildingCentroids: no building data")
            return
        }
        guard mapView != nil else { return }
        do {
            let pointData = try Self.pointFeatureCollectionFromBuildingCentroids(data)
            guard let parsed = try? JSONSerialization.jsonObject(with: pointData) as? [String: Any],
                  let feats = parsed["features"] as? [[String: Any]] else {
                print("🔍 [MapLayer] updateAddressesFromBuildingCentroids: centroid extraction produced no features")
                return
            }
            if feats.isEmpty {
                print("🔍 [MapLayer] updateAddressesFromBuildingCentroids: 0 centroids (building geometry may not be Polygon/MultiPolygon)")
                return
            }
            updateAddresses(pointData)
            print("✅ [MapLayer] Updated addresses from \(feats.count) building centroids (circle extrusions fallback)")
        } catch {
            print("❌ [MapLayer] Error building centroid points: \(error)")
        }
    }
    
    /// Convert GeoJSON FeatureCollection of Point features to Polygon features (circle rings) for fill extrusion
    private static func convertAddressPointsToCirclePolygons(_ pointGeoJSONData: Data, radiusMeters: Double = 2.7, height: Double = 10.8, segments: Int = 20) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: pointGeoJSONData) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            print("🔍 [MapLayer] convertAddressPointsToCirclePolygons: no features array in GeoJSON")
            return pointGeoJSONData
        }
        if features.isEmpty {
            print("🔍 [MapLayer] convertAddressPointsToCirclePolygons: input has 0 features")
        }
        let earth = 6_378_137.0
        var polygonFeatures: [[String: Any]] = []
        var skipped = 0
        
        for feature in features {
            guard let geom = feature["geometry"] as? [String: Any] else { skipped += 1; continue }
            guard geom["type"] as? String == "Point" else { skipped += 1; continue }
            guard let coordsAny = geom["coordinates"],
                  let coords = pointCoordinatesFromAny(coordsAny), coords.count >= 2 else {
                skipped += 1
                continue
            }
            let lon = coords[0]
            let lat = coords[1]
            guard lon.isFinite, lat.isFinite, abs(lat) < 89 else { continue }
            let latRad = lat * .pi / 180
            let cosLat = max(cos(latRad), 1e-10)
            var ring: [[Double]] = []
            for i in 0...segments {
                let theta = 2 * .pi * Double(i) / Double(segments)
                let dx = radiusMeters * cos(theta)
                let dy = radiusMeters * sin(theta)
                let dLat = (dy / earth) * 180 / .pi
                let dLon = (dx / (earth * cosLat)) * 180 / .pi
                let x = lon + dLon
                let y = lat + dLat
                guard x.isFinite, y.isFinite else { continue }
                ring.append([x, y])
            }
            guard ring.count == segments + 1 else { continue }
            var props = (feature["properties"] as? [String: Any]) ?? [:]
            props["height"] = height.isFinite ? height : 10.8
            // promoteId is "id" – ensure id is in properties and at root so setFeatureState can match (prefer address_id when present)
            var featureId: String?
            if let existing = props["id"] as? String, !existing.isEmpty {
                featureId = existing
            } else if let addressId = props["address_id"] as? String, !addressId.isEmpty {
                featureId = addressId
                props["id"] = addressId
            } else if let rootId = feature["id"] as? String, !rootId.isEmpty {
                featureId = rootId
                props["id"] = rootId
            } else if let rootId = feature["id"] as? Int {
                featureId = String(rootId)
                props["id"] = featureId
            }
            // Normalize UUID strings to lowercase so they match Postgres JSON and setFeatureState lookup
            if let idStr = featureId {
                let normalizedId = idStr.contains("-") ? idStr.lowercased() : idStr
                props["id"] = normalizedId
                featureId = normalizedId
            }
            var polygonFeature: [String: Any] = [
                "type": "Feature",
                "geometry": ["type": "Polygon", "coordinates": [ring]],
                "properties": props
            ]
            if let idStr = featureId {
                polygonFeature["id"] = idStr
            }
            polygonFeatures.append(polygonFeature)
        }
        if skipped > 0 {
            print("🔍 [MapLayer] convertAddressPointsToCirclePolygons: skipped \(skipped) features (not Point or bad coords)")
        }
        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": polygonFeatures
        ]
        return try stableJSONData(withJSONObject: collection)
    }
    
    /// Update roads source with new GeoJSON data
    func updateRoads(_ data: Data) {
        guard let mapView = mapView else { return }
        let signature = Self.sourceSignature(for: data)
        guard lastRoadsSourceSignature != signature else { return }
        
        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.roadsSourceId, geoJSON: geoJSON)
            lastRoadsSourceSignature = signature
            print("✅ [MapLayer] Updated roads source")
        } catch {
            print("❌ [MapLayer] Error updating roads: \(error)")
        }
    }

    /// Update campaign parcel polygons with campaign-scoped GeoJSON.
    func updateParcels(_ data: Data) {
        guard let mapView = mapView else { return }
        let signature = Self.sourceSignature(for: data)
        guard lastParcelsSourceSignature != signature else { return }

        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.parcelsSourceId, geoJSON: geoJSON)
            lastParcelsSourceSignature = signature

            let featureCount = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["features"] as? [[String: Any]] }?
                .count ?? 0
            print("✅ [MapLayer] Updated parcels source features=\(featureCount)")
            replayCachedAddressFeatureStates(reason: "parcels_source_update")
        } catch {
            print("❌ [MapLayer] Error updating parcels: \(error)")
        }
    }
    
    // MARK: - Real-time Feature State Updates
    
    /// Update a building's feature state for instant color change (no re-render).
    /// Uses lowercase featureId so it matches promoteId values in the source (buildings use lowercase gers_id).
    func updateBuildingState(gersId: String, status: String, scansTotal: Int, visitOwner: String? = nil, isLinked: Bool? = nil) {
        let featureId = gersId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !featureId.isEmpty else { return }

        var state = buildingFeatureStateCache[featureId] ?? [:]
        state["status"] = status
        state["scans_total"] = scansTotal
        state["qr_scanned"] = scansTotal > 0
        state["visit_owner"] = visitOwner ?? ""
        if let isLinked {
            state["is_linked"] = isLinked
        }

        if let existing = buildingFeatureStateCache[featureId],
           existing["status"] as? String == status,
           existing["scans_total"] as? Int == scansTotal,
           existing["qr_scanned"] as? Bool == (scansTotal > 0),
           existing["visit_owner"] as? String == (visitOwner ?? ""),
           isLinked.map({ (existing["is_linked"] as? Bool) == $0 }) ?? true {
            return
        }

        buildingFeatureStateCache[featureId] = state
        guard let mapView else { return }
        applyBuildingFeatureState(featureId: featureId, state: state, mapView: mapView, logSuccess: false)
    }

    /// Update an address circle's feature state (for 3D address pillars). Use addressId (UUID string) as featureId.
    /// Normalizes addressId to lowercase so it matches Postgres JSON (UUIDs are lowercase there).
    func updateAddressState(addressId: String, status: String, scansTotal: Int, visitOwner: String? = nil) {
        let normalizedId = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedId.isEmpty else { return }

        let state: [String: Any] = [
            "status": status,
            "scans_total": scansTotal,
            "qr_scanned": scansTotal > 0,
            "visit_owner": visitOwner ?? ""
        ]

        if let existing = addressFeatureStateCache[normalizedId],
           existing["status"] as? String == status,
           existing["scans_total"] as? Int == scansTotal,
           existing["qr_scanned"] as? Bool == (scansTotal > 0),
           existing["visit_owner"] as? String == (visitOwner ?? "") {
            return
        }

        addressFeatureStateCache[normalizedId] = state
        guard let mapView else { return }
        applyAddressFeatureState(featureId: normalizedId, state: state, mapView: mapView, logSuccess: false)
    }

    private func applyBuildingFeatureState(
        featureId: String,
        state: [String: Any],
        mapView: MapView,
        logSuccess: Bool
    ) {
        if mapView.mapboxMap.sourceExists(withId: Self.buildingsSourceId) {
            mapView.mapboxMap.setFeatureState(
                sourceId: Self.buildingsSourceId,
                sourceLayerId: nil,
                featureId: featureId,
                state: state
            ) { result in
                switch result {
                case .success:
                    if logSuccess {
                        print("✅ [MapLayer] Updated feature state for \(featureId)")
                    }
                case .failure(let error):
                    print("❌ [MapLayer] Error updating feature state: \(error)")
                }
            }
        }

        if let diamondBuildingLayer = installedDiamondManifest?.sourceLayers?.buildings,
           let diamondBuildingSourceId = existingDiamondSourceId(
            preferred: VectorTileDiamondGeometryProvider.buildingSourceId,
            on: mapView.mapboxMap
           ) {
            mapView.mapboxMap.setFeatureState(
                sourceId: diamondBuildingSourceId,
                sourceLayerId: diamondBuildingLayer,
                featureId: featureId,
                state: state
            ) { result in
                switch result {
                case .success:
                    if logSuccess {
                        print("💎 [DIAMOND] Updated building feature state for \(featureId)")
                    }
                case .failure(let error):
                    print("❌ [DIAMOND] Error updating building feature state: \(error)")
                }
            }
        }

        updateDiamondParcelState(featureId: featureId, state: state, logSuccess: logSuccess)
    }

    private func applyAddressFeatureState(
        featureId normalizedId: String,
        state: [String: Any],
        mapView: MapView,
        logSuccess: Bool
    ) {
        if mapView.mapboxMap.sourceExists(withId: Self.addressesSourceId) {
            mapView.mapboxMap.setFeatureState(
                sourceId: Self.addressesSourceId,
                sourceLayerId: nil,
                featureId: normalizedId,
                state: state
            ) { result in
                switch result {
                case .success:
                    if logSuccess {
                        print("✅ [MapLayer] Updated address feature state for \(normalizedId)")
                    }
                case .failure(let error):
                    print("❌ [MapLayer] Error updating address feature state: \(error)")
                }
            }
        }

        if mapView.mapboxMap.sourceExists(withId: Self.parcelsSourceId) {
            mapView.mapboxMap.setFeatureState(
                sourceId: Self.parcelsSourceId,
                sourceLayerId: nil,
                featureId: normalizedId,
                state: state,
                callback: { _ in }
            )
        }

        if let diamondBuildingLayer = installedDiamondManifest?.sourceLayers?.buildings,
           let diamondBuildingSourceId = existingDiamondSourceId(
            preferred: VectorTileDiamondGeometryProvider.buildingSourceId,
            on: mapView.mapboxMap
           ) {
            mapView.mapboxMap.setFeatureState(
                sourceId: diamondBuildingSourceId,
                sourceLayerId: diamondBuildingLayer,
                featureId: normalizedId,
                state: state
            ) { result in
                switch result {
                case .success:
                    if logSuccess {
                        print("💎 [DIAMOND] Updated building feature state for address \(normalizedId)")
                    }
                case .failure(let error):
                    print("❌ [DIAMOND] Error updating building feature state: \(error)")
                }
            }
        }

        if let diamondAddressLayer = installedDiamondManifest?.sourceLayers?.primaryAddressLayer,
           let diamondAddressSourceId = existingDiamondSourceId(
            preferred: VectorTileDiamondGeometryProvider.addressSourceId,
            on: mapView.mapboxMap
           ) {
            mapView.mapboxMap.setFeatureState(
                sourceId: diamondAddressSourceId,
                sourceLayerId: diamondAddressLayer,
                featureId: normalizedId,
                state: state
            ) { result in
                switch result {
                case .success:
                    if logSuccess {
                        print("💎 [DIAMOND] Updated address feature state for \(normalizedId)")
                    }
                case .failure(let error):
                    print("❌ [DIAMOND] Error updating address feature state: \(error)")
                }
            }
        }

        updateDiamondParcelState(featureId: normalizedId, state: state, logSuccess: logSuccess)
    }

    private func replayCachedFeatureStates(reason: String) {
        replayCachedBuildingFeatureStates(reason: reason)
        replayCachedAddressFeatureStates(reason: reason)
    }

    private func replayCachedBuildingFeatureStates(reason: String) {
        guard let mapView, !buildingFeatureStateCache.isEmpty else { return }
        for (featureId, state) in buildingFeatureStateCache {
            applyBuildingFeatureState(featureId: featureId, state: state, mapView: mapView, logSuccess: false)
        }
        replayTownhomeOverlaySelectionStates(reason: reason)
        print("🧪 [MAP_DEBUG] feature_state_replay kind=buildings reason=\(reason) count=\(buildingFeatureStateCache.count)")
    }

    private func replayCachedAddressFeatureStates(reason: String) {
        guard let mapView, !addressFeatureStateCache.isEmpty else { return }
        for (featureId, state) in addressFeatureStateCache {
            applyAddressFeatureState(featureId: featureId, state: state, mapView: mapView, logSuccess: false)
        }
        print("🧪 [MAP_DEBUG] feature_state_replay kind=addresses reason=\(reason) count=\(addressFeatureStateCache.count)")
    }

    private func existingDiamondSourceId(preferred: String, on map: MapboxMap) -> String? {
        if map.sourceExists(withId: preferred) {
            return preferred
        }
        if preferred != VectorTileDiamondGeometryProvider.sourceId,
           map.sourceExists(withId: VectorTileDiamondGeometryProvider.sourceId) {
            return VectorTileDiamondGeometryProvider.sourceId
        }
        return nil
    }

    private func replayTownhomeOverlaySelectionStates(reason: String) {
        guard let mapView,
              mapView.mapboxMap.sourceExists(withId: Self.townhomeOverlaySourceId),
              !townhomeOverlayFeatureIdsByBuildingIdentifier.isEmpty else {
            return
        }

        let selectedBuildingIds = buildingFeatureStateCache.compactMap { featureId, state -> String? in
            (state["selected"] as? Bool) == true ? featureId : nil
        }
        let selectedOverlayFeatureIds = overlayFeatureIds(forBuildingIdentifiers: selectedBuildingIds)
        guard !selectedOverlayFeatureIds.isEmpty else { return }
        applyTownhomeOverlaySelection(featureIds: selectedOverlayFeatureIds, isSelected: true, mapView: mapView)
        print("🧪 [MAP_DEBUG] feature_state_replay kind=townhomes reason=\(reason) count=\(selectedOverlayFeatureIds.count)")
    }

    private func overlayFeatureIds(forBuildingIdentifiers buildingIdentifiers: [String]) -> [String] {
        var seen = Set<String>()
        return buildingIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { townhomeOverlayFeatureIdsByBuildingIdentifier[$0] ?? [] }
            .filter { seen.insert($0).inserted }
    }

    private func applyTownhomeOverlaySelection(featureIds: [String], isSelected: Bool, mapView: MapView) {
        guard mapView.mapboxMap.sourceExists(withId: Self.townhomeOverlaySourceId) else { return }
        for featureId in featureIds {
            mapView.mapboxMap.setFeatureState(
                sourceId: Self.townhomeOverlaySourceId,
                sourceLayerId: nil,
                featureId: featureId,
                state: ["selected": isSelected],
                callback: { _ in }
            )
        }
    }

    private func updateDiamondParcelState(featureId: String, state: [String: Any], logSuccess: Bool = true) {
        guard let mapView = mapView,
              let parcelLayer = installedDiamondManifest?.sourceLayers?.parcels,
              let diamondParcelSourceId = existingDiamondSourceId(
                preferred: VectorTileDiamondGeometryProvider.parcelSourceId,
                on: mapView.mapboxMap
              ) else {
            return
        }

        mapView.mapboxMap.setFeatureState(
            sourceId: diamondParcelSourceId,
            sourceLayerId: parcelLayer,
            featureId: featureId.lowercased(),
            state: state
        ) { result in
            switch result {
            case .success:
                if logSuccess {
                    print("💎 [DIAMOND] Updated parcel feature state for \(featureId)")
                }
            case .failure(let error):
                print("❌ [DIAMOND] Error updating parcel feature state: \(error)")
            }
        }
    }

    func updateBuildingSelection(gersId: String, isSelected: Bool) {
        updateBuildingSelection(identifiers: [gersId], isSelected: isSelected)
    }

    func updateBuildingSelection(identifiers: [String], isSelected: Bool) {
        guard let mapView = mapView else { return }
        var seen = Set<String>()
        let featureIds = identifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !featureIds.isEmpty else { return }

        for featureId in featureIds {
            var state = buildingFeatureStateCache[featureId] ?? [:]
            state["selected"] = isSelected
            buildingFeatureStateCache[featureId] = state
            applyBuildingFeatureState(featureId: featureId, state: state, mapView: mapView, logSuccess: false)
        }

        let overlayFeatureIds = overlayFeatureIds(forBuildingIdentifiers: featureIds)
        applyTownhomeOverlaySelection(featureIds: overlayFeatureIds, isSelected: isSelected, mapView: mapView)
    }

    func updateAddressSelection(addressId: String, isSelected: Bool) {
        guard let mapView = mapView else { return }
        let featureId = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !featureId.isEmpty else { return }
        let state: [String: Any] = ["selected": isSelected]

        mapView.mapboxMap.setFeatureState(
            sourceId: Self.addressesSourceId,
            sourceLayerId: nil,
            featureId: featureId,
            state: state,
            callback: { _ in }
        )

        if mapView.mapboxMap.sourceExists(withId: Self.parcelsSourceId) {
            mapView.mapboxMap.setFeatureState(
                sourceId: Self.parcelsSourceId,
                sourceLayerId: nil,
                featureId: featureId,
                state: state,
                callback: { _ in }
            )
        }

        if let diamondBuildingLayer = installedDiamondManifest?.sourceLayers?.buildings,
           let diamondBuildingSourceId = existingDiamondSourceId(
            preferred: VectorTileDiamondGeometryProvider.buildingSourceId,
            on: mapView.mapboxMap
           ) {
            mapView.mapboxMap.setFeatureState(
                sourceId: diamondBuildingSourceId,
                sourceLayerId: diamondBuildingLayer,
                featureId: featureId,
                state: state,
                callback: { _ in }
            )
        }

        if let diamondAddressLayer = installedDiamondManifest?.sourceLayers?.primaryAddressLayer,
           let diamondAddressSourceId = existingDiamondSourceId(
            preferred: VectorTileDiamondGeometryProvider.addressSourceId,
            on: mapView.mapboxMap
           ) {
            mapView.mapboxMap.setFeatureState(
                sourceId: diamondAddressSourceId,
                sourceLayerId: diamondAddressLayer,
                featureId: featureId,
                state: state,
                callback: { _ in }
            )
        }

        updateDiamondParcelState(featureId: featureId, state: state)
    }
    
    // MARK: - Status Filters
    
    /// Update layer filter based on status toggles
    func updateStatusFilter() {
        guard let mapView = mapView else { return }

        do {
            var updatedAnyLayer = false
            if mapView.mapboxMap.layerExists(withId: Self.buildingsLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.buildingsLayerId, type: FillExtrusionLayer.self) { layer in
                    layer.filter = Self.buildingsStatusFilter(
                        showQrScanned: showQrScanned,
                        showConversations: showConversations,
                        showTouched: showTouched,
                        showUntouched: showUntouched
                    )
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.buildingsLeadGlowLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.buildingsLeadGlowLayerId, type: LineLayer.self) { layer in
                    layer.filter = Self.buildingsStatusFilter(
                        showQrScanned: showQrScanned,
                        showConversations: showConversations,
                        showTouched: showTouched,
                        showUntouched: showUntouched
                    )
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.townhomeOverlayLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.townhomeOverlayLayerId, type: FillExtrusionLayer.self) { layer in
                    layer.filter = Self.townhomeOverlayFilter(
                        showConversations: showConversations,
                        showTouched: showTouched,
                        showUntouched: showUntouched
                    )
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.townhomeSliceOutlineLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.townhomeSliceOutlineLayerId, type: LineLayer.self) { layer in
                    layer.filter = Self.townhomeOverlayFilter(
                        showConversations: showConversations,
                        showTouched: showTouched,
                        showUntouched: showUntouched
                    )
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.townhomeOutlineLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.townhomeOutlineLayerId, type: LineLayer.self) { layer in
                    layer.filter = Self.townhomeOverlayFilter(
                        showConversations: showConversations,
                        showTouched: showTouched,
                        showUntouched: showUntouched
                    )
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.townhomeDividerLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.townhomeDividerLayerId, type: LineLayer.self) { layer in
                    layer.filter = Self.townhomeDividerFilter()
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.townhomeDividerStripLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.townhomeDividerStripLayerId, type: FillExtrusionLayer.self) { layer in
                    layer.filter = Self.townhomeDividerStripFilter()
                }
                updatedAnyLayer = true
            }
            if mapView.mapboxMap.layerExists(withId: Self.townhomeLeadGlowLayerId) {
                try mapView.mapboxMap.updateLayer(withId: Self.townhomeLeadGlowLayerId, type: LineLayer.self) { layer in
                    layer.filter = Self.townhomeOverlayFilter(
                        showConversations: showConversations,
                        showTouched: showTouched,
                        showUntouched: showUntouched
                    )
                }
                updatedAnyLayer = true
            }
            guard updatedAnyLayer else { return }
            print("✅ [MapLayer] Updated status filter")
        } catch {
            print("❌ [MapLayer] Error updating filter: \(error)")
        }
    }

    private static func buildingsStatusFilter(
        showQrScanned: Bool,
        showConversations: Bool,
        showTouched: Bool,
        showUntouched: Bool
    ) -> Exp {
        Exp(.all) {
            Exp(.match) {
                Exp(.geometryType)
                "Polygon"
                true
                "MultiPolygon"
                true
                false
            }
            Exp(.switchCase) {
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "scans_total" }
                        Exp(.get) { "scans_total" }
                        0
                    }
                    0
                }
                showQrScanned
                Exp(.match) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot"
                    showConversations
                    "talked"
                    showConversations
                    "appointment"
                    showConversations
                    "lead"
                    showConversations
                    "hot_lead"
                    showConversations
                    "flyer_unvisited"
                    showUntouched
                    "visited"
                    showTouched
                    "do_not_knock"
                    showTouched
                    "delivered"
                    showTouched
                    "no_answer"
                    showTouched
                    "future_seller"
                    showConversations
                    "follow_up"
                    showConversations
                    "not_visited"
                    showUntouched
                    false
                }
            }
        }
    }

    private static func townhomeOverlayFilter(
        showConversations: Bool,
        showTouched: Bool,
        showUntouched: Bool
    ) -> Exp {
        Exp(.all) {
            Exp(.match) {
                Exp(.geometryType)
                "Polygon"
                true
                "MultiPolygon"
                true
                false
            }
            Exp(.match) {
                Exp(.get) { "segment_status" }
                "hot"
                showConversations
                "lead"
                showConversations
                "appointment"
                showConversations
                "hot_lead"
                showConversations
                "future_seller"
                showConversations
                "follow_up"
                showConversations
                "flyer_unvisited"
                showUntouched
                "visited"
                showTouched
                "do_not_knock"
                showTouched
                "no_answer"
                showTouched
                "not_visited"
                showUntouched
                false
            }
        }
    }

    private static func townhomeDividerFilter() -> Exp {
        Exp(.all) {
            Exp(.eq) {
                Exp(.geometryType)
                "LineString"
            }
            Exp(.eq) {
                Exp(.get) { "feature_kind" }
                "divider"
            }
        }
    }

    private static func townhomeDividerStripFilter() -> Exp {
        Exp(.all) {
            Exp(.eq) {
                Exp(.geometryType)
                "Polygon"
            }
            Exp(.eq) {
                Exp(.get) { "feature_kind" }
                "divider_strip"
            }
        }
    }

    private struct OverlayAddressContext {
        let id: UUID
        let buildingGersId: String
        let houseNumber: String?
        let streetName: String?
        let formatted: String?
    }

    private enum TownhomeAddressResolutionSource: String {
        case explicitMap = "explicit_map"
        case embeddedFallback = "embedded_fallback"
    }

    private struct TownhomeAddressResolution {
        let addresses: [OverlayAddressContext]
        let linkedCount: Int
        let source: TownhomeAddressResolutionSource
    }

#if DEBUG
    private struct TownhomeOverlayAudit {
        let buildingId: String
        let source: TownhomeAddressResolutionSource
        let linkedCount: Int
        let renderedSliceCount: Int
    }
#endif

    private struct ProjectedPoint {
        let x: Double
        let y: Double
    }

    private struct RotatedPoint {
        let u: Double
        let v: Double
    }

    private static func orderedAddressResolutionForTownhome(
        buildingIdentifiers: [String],
        embeddedAddressIds: [UUID],
        fallbackAddressId: String?,
        addressesById: [UUID: OverlayAddressContext],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) -> TownhomeAddressResolution {
        if let mappedIds = explicitlyMappedAddressIds(
            for: buildingIdentifiers,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
        ) {
            let normalizedIds = dedupePreservingOrder(mappedIds)
            return TownhomeAddressResolution(
                addresses: normalizedIds.compactMap { addressesById[$0] },
                linkedCount: normalizedIds.count,
                source: .explicitMap
            )
        }

        let identifierSet = Set(buildingIdentifiers)
        let normalizedIds = dedupePreservingOrder(embeddedAddressIds)
        var ordered = normalizedIds.compactMap { addressesById[$0] }
        let seen = Set(ordered.map(\.id))

        let matchedAddresses = addressesById.values
            .filter { identifierSet.contains($0.buildingGersId) && !seen.contains($0.id) }
            .sorted(by: compareOverlayAddresses)

        ordered.append(contentsOf: matchedAddresses)
        if !ordered.isEmpty {
            return TownhomeAddressResolution(
                addresses: ordered,
                linkedCount: ordered.count,
                source: .embeddedFallback
            )
        }

        if let fallbackAddressId,
           let uuid = UUID(uuidString: fallbackAddressId),
           let address = addressesById[uuid] {
            return TownhomeAddressResolution(
                addresses: [address],
                linkedCount: 1,
                source: .embeddedFallback
            )
        }

        return TownhomeAddressResolution(
            addresses: [],
            linkedCount: 0,
            source: .embeddedFallback
        )
    }

    private static func explicitlyMappedAddressIds(
        for buildingIdentifiers: [String],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) -> [UUID]? {
        let normalizedMap = normalizedOrderedAddressIdsByBuilding(orderedAddressIdsByBuilding)
        guard !normalizedMap.isEmpty else { return nil }

        var foundExplicitEntry = false
        var mappedIds: [UUID] = []
        for identifier in buildingIdentifiers {
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty,
                  let ids = normalizedMap[normalized] else { continue }
            foundExplicitEntry = true
            mappedIds.append(contentsOf: ids)
        }

        return foundExplicitEntry ? dedupePreservingOrder(mappedIds) : nil
    }

    private static func normalizedOrderedAddressIdsByBuilding(
        _ orderedAddressIdsByBuilding: [String: [UUID]]
    ) -> [String: [UUID]] {
        var normalized: [String: [UUID]] = [:]
        for (identifier, addressIds) in orderedAddressIdsByBuilding {
            let key = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            normalized[key, default: []].append(contentsOf: addressIds)
        }

        for key in Array(normalized.keys) {
            normalized[key] = dedupePreservingOrder(normalized[key] ?? [])
        }
        return normalized
    }

    private static func overlayAddressContextsById(_ addresses: [AddressFeature]) -> [UUID: OverlayAddressContext] {
        var contexts: [UUID: OverlayAddressContext] = [:]
        for feature in addresses {
            guard let idString = feature.properties.id ?? feature.id,
                  let id = UUID(uuidString: idString) else { continue }
            contexts[id] = OverlayAddressContext(
                id: id,
                buildingGersId: (feature.properties.buildingGersId ?? feature.properties.gersId ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName,
                formatted: feature.properties.formatted
            )
        }
        return contexts
    }

#if DEBUG
    private static func townhomeOverlayAuditCounts(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) -> [TownhomeOverlayAudit] {
        let addressContextsById = overlayAddressContextsById(addresses)
        return buildings.compactMap { building in
            let buildingId = (building.properties.canonicalBuildingIdentifier ?? building.id ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !buildingId.isEmpty else { return nil }
            let resolution = orderedAddressResolutionForTownhome(
                buildingIdentifiers: normalizedBuildingIdentifiers(for: building),
                embeddedAddressIds: building.properties.addressUUIDs,
                fallbackAddressId: building.properties.addressId,
                addressesById: addressContextsById,
                orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
            )
            return TownhomeOverlayAudit(
                buildingId: buildingId,
                source: resolution.source,
                linkedCount: resolution.linkedCount,
                renderedSliceCount: shouldRenderTownhomeOverlay(for: resolution.addresses)
                    ? resolution.addresses.count
                    : 0
            )
        }
    }
#endif

    private static func shouldRenderTownhomeOverlay(for addresses: [OverlayAddressContext]) -> Bool {
        Set(addresses.map(\.id)).count >= Self.townhomeOverlayMinimumUnitCount
    }

    private static func normalizedBuildingIdentifiers(for building: BuildingFeature) -> [String] {
        let rawValues = building.properties.buildingIdentifierCandidates.map(Optional.some) + [
            building.id,
            building.properties.id,
            building.properties.gersId,
            building.properties.buildingId,
            building.properties.publicBuildingId,
            building.properties.canonicalBuildingId,
            building.properties.canonicalBuildingIdentifier
        ]

        var seen = Set<String>()
        return rawValues
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func compareOverlayAddresses(_ lhs: OverlayAddressContext, _ rhs: OverlayAddressContext) -> Bool {
        let lhsStreet = normalizedStreetName(for: lhs)
        let rhsStreet = normalizedStreetName(for: rhs)
        if lhsStreet != rhsStreet {
            return lhsStreet.localizedStandardCompare(rhsStreet) == .orderedAscending
        }

        let lhsHouse = houseNumberSortParts(
            houseNumber: lhs.houseNumber,
            formatted: lhs.formatted
        )
        let rhsHouse = houseNumberSortParts(
            houseNumber: rhs.houseNumber,
            formatted: rhs.formatted
        )

        switch (lhsHouse.number, rhsHouse.number) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if lhsHouse.suffix != rhsHouse.suffix {
            return lhsHouse.suffix.localizedStandardCompare(rhsHouse.suffix) == .orderedAscending
        }

        let lhsFormatted = (lhs.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsFormatted = (rhs.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return lhsFormatted.localizedStandardCompare(rhsFormatted) == .orderedAscending
    }

    private static func normalizedStreetName(for address: OverlayAddressContext) -> String {
        let explicitStreet = (address.streetName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitStreet.isEmpty {
            return explicitStreet
        }

        let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        return streetOnly.replacingOccurrences(
            of: #"^\s*\d+[A-Za-z\-]*\s+"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func houseNumberSortParts(houseNumber: String?, formatted: String?) -> (number: Int?, suffix: String) {
        let rawHouseNumber = (houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue: String
        if !rawHouseNumber.isEmpty {
            rawValue = rawHouseNumber
        } else {
            let formatted = (formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
            rawValue = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        }

        let normalized = rawValue.uppercased()
        guard let range = normalized.range(of: #"^\d+"#, options: .regularExpression) else {
            return (nil, normalized)
        }

        let number = Int(normalized[range])
        let suffix = normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (number, suffix)
    }

    private static func dedupePreservingOrder(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private static func overlaySegmentStatus(for status: AddressStatus?) -> String {
        guard let status else { return "not_visited" }
        switch status {
        case .talked:
            return "hot"
        case .appointment:
            return "appointment"
        case .futureSeller:
            return "future_seller"
        case .hotLead:
            return "lead"
        case .doNotKnock:
            return "do_not_knock"
        case .noAnswer:
            return "no_answer"
        case .delivered:
            return "visited"
        case .none, .untouched:
            return "not_visited"
        }
    }

    private static func overlayVisitOwner(
        for row: AddressStatusRow?,
        currentUserId: UUID?
    ) -> String {
        guard let row else { return "" }
        switch row.status {
        case .delivered:
            guard let actorUserId = row.lastActionBy else { return "" }
            if let currentUserId, actorUserId != currentUserId {
                return "teammate"
            }
            return "self"
        default:
            return ""
        }
    }

    private static func polygonRings(from geometry: MapFeatureGeoJSONGeometry) -> [[[Double]]] {
        if let polygon = geometry.asPolygon, let outerRing = cleanedOuterRing(polygon.first) {
            return [outerRing]
        }

        if let multiPolygon = geometry.asMultiPolygon {
            return multiPolygon.compactMap { cleanedOuterRing($0.first) }
        }

        return []
    }

    private static func cleanedOuterRing(_ ring: [[Double]]?) -> [[Double]]? {
        guard var ring, ring.count >= 4 else { return nil }
        if ring.first == ring.last {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return nil }
        ring.append(ring[0])
        return ring
    }

    private static func slicedPolygons(
        polygons: [[[Double]]],
        startFraction: Double,
        endFraction: Double
    ) -> [[[Double]]]? {
        guard !polygons.isEmpty, endFraction > startFraction else { return nil }

        let center = projectedCenter(for: polygons)
        let metersPerLat = 111_320.0
        let metersPerLon = max(cos(center.lat * .pi / 180.0) * metersPerLat, 0.0001)

        let projectedPolygons: [[ProjectedPoint]] = polygons.compactMap { polygon in
            let openRing = polygon.dropLast()
            guard openRing.count >= 3 else { return nil }
            return openRing.map { point in
                ProjectedPoint(
                    x: (point[0] - center.lon) * metersPerLon,
                    y: (point[1] - center.lat) * metersPerLat
                )
            }
        }
        let allPoints = projectedPolygons.flatMap { $0 }
        guard allPoints.count >= 3 else { return nil }

        let angle = principalAxisAngle(for: allPoints)
        let rotatedPolygons = projectedPolygons.map { polygon in
            polygon.map { point in
                RotatedPoint(
                    u: point.x * cos(angle) + point.y * sin(angle),
                    v: -point.x * sin(angle) + point.y * cos(angle)
                )
            }
        }

        let allU = rotatedPolygons.flatMap { $0.map(\.u) }
        guard let minU = allU.min(), let maxU = allU.max(), maxU - minU > 0.01 else { return nil }

        let sliceStart = minU + (maxU - minU) * startFraction
        let sliceEnd = minU + (maxU - minU) * endFraction

        let clippedPolygons: [[[Double]]] = rotatedPolygons.compactMap { polygon in
            let clipped = clipPolygon(polygon, minU: sliceStart, maxU: sliceEnd)
            guard clipped.count >= 3 else { return nil }

            var ring: [[Double]] = clipped.map { point in
                let x = point.u * cos(angle) - point.v * sin(angle)
                let y = point.u * sin(angle) + point.v * cos(angle)
                let lon = center.lon + (x / metersPerLon)
                let lat = center.lat + (y / metersPerLat)
                return [lon, lat]
            }
            guard ring.count >= 3 else { return nil }
            ring.append(ring[0])
            return ring
        }

        return clippedPolygons.isEmpty ? nil : clippedPolygons
    }

    private static func townhomeDividerLineStrings(
        polygons: [[[Double]]],
        unitCount: Int
    ) -> [[[Double]]] {
        guard unitCount > 1, !polygons.isEmpty else { return [] }

        let center = projectedCenter(for: polygons)
        let metersPerLat = 111_320.0
        let metersPerLon = max(cos(center.lat * .pi / 180.0) * metersPerLat, 0.0001)

        let projectedPolygons: [[ProjectedPoint]] = polygons.compactMap { polygon in
            let openRing = polygon.dropLast()
            guard openRing.count >= 3 else { return nil }
            return openRing.map { point in
                ProjectedPoint(
                    x: (point[0] - center.lon) * metersPerLon,
                    y: (point[1] - center.lat) * metersPerLat
                )
            }
        }
        let allPoints = projectedPolygons.flatMap { $0 }
        guard allPoints.count >= 3 else { return [] }

        let angle = principalAxisAngle(for: allPoints)
        let rotatedPolygons = projectedPolygons.map { polygon in
            polygon.map { point in
                RotatedPoint(
                    u: point.x * cos(angle) + point.y * sin(angle),
                    v: -point.x * sin(angle) + point.y * cos(angle)
                )
            }
        }
        let allU = rotatedPolygons.flatMap { $0.map(\.u) }
        guard let minU = allU.min(), let maxU = allU.max(), maxU - minU > 0.01 else {
            return []
        }

        func coordinate(from point: RotatedPoint) -> [Double] {
            let x = point.u * cos(angle) - point.v * sin(angle)
            let y = point.u * sin(angle) + point.v * cos(angle)
            return [
                center.lon + (x / metersPerLon),
                center.lat + (y / metersPerLat)
            ]
        }

        var lines: [[[Double]]] = []
        let epsilon = 0.000001
        for divider in 1..<unitCount {
            let boundaryU = minU + (maxU - minU) * (Double(divider) / Double(unitCount))
            for polygon in rotatedPolygons {
                guard polygon.count >= 3 else { continue }
                var intersections: [RotatedPoint] = []

                for index in polygon.indices {
                    let current = polygon[index]
                    let next = polygon[(index + 1) % polygon.count]
                    let currentDelta = current.u - boundaryU
                    let nextDelta = next.u - boundaryU
                    if abs(currentDelta) < epsilon && abs(nextDelta) < epsilon {
                        continue
                    }
                    guard (currentDelta <= epsilon && nextDelta >= -epsilon)
                            || (nextDelta <= epsilon && currentDelta >= -epsilon) else {
                        continue
                    }
                    let deltaU = next.u - current.u
                    guard abs(deltaU) > epsilon else { continue }
                    let t = (boundaryU - current.u) / deltaU
                    guard t >= -epsilon, t <= 1 + epsilon else { continue }
                    intersections.append(
                        RotatedPoint(
                            u: boundaryU,
                            v: current.v + (next.v - current.v) * t
                        )
                    )
                }

                intersections.sort { $0.v < $1.v }
                intersections = intersections.reduce(into: []) { result, point in
                    if let last = result.last, abs(last.v - point.v) < 0.01 {
                        return
                    }
                    result.append(point)
                }

                var index = 0
                while index + 1 < intersections.count {
                    let start = intersections[index]
                    let end = intersections[index + 1]
                    if abs(end.v - start.v) > 0.05 {
                        lines.append([coordinate(from: start), coordinate(from: end)])
                    }
                    index += 2
                }
            }
        }
        return lines
    }

    private static func dividerStripRing(from line: [[Double]], widthMeters: Double) -> [[Double]]? {
        guard line.count >= 2, widthMeters > 0 else { return nil }
        guard let start = line.first, let end = line.last, start.count >= 2, end.count >= 2 else {
            return nil
        }

        let startLon = start[0]
        let startLat = start[1]
        let endLon = end[0]
        let endLat = end[1]
        let midpointLat = (startLat + endLat) / 2.0
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = max(cos(midpointLat * .pi / 180.0) * metersPerDegreeLat, 1.0)
        let dxMeters = (endLon - startLon) * metersPerDegreeLon
        let dyMeters = (endLat - startLat) * metersPerDegreeLat
        let lengthMeters = hypot(dxMeters, dyMeters)
        guard lengthMeters.isFinite, lengthMeters > 0.05 else { return nil }

        let halfWidth = widthMeters / 2.0
        let normalXMeters = (-dyMeters / lengthMeters) * halfWidth
        let normalYMeters = (dxMeters / lengthMeters) * halfWidth
        let deltaLon = normalXMeters / metersPerDegreeLon
        let deltaLat = normalYMeters / metersPerDegreeLat

        return [
            [startLon + deltaLon, startLat + deltaLat],
            [endLon + deltaLon, endLat + deltaLat],
            [endLon - deltaLon, endLat - deltaLat],
            [startLon - deltaLon, startLat - deltaLat],
            [startLon + deltaLon, startLat + deltaLat]
        ]
    }

    private static func insetPolygonRing(_ ring: [[Double]], insetMeters: Double) -> [[Double]]? {
        guard ring.count >= 4, insetMeters > 0 else { return nil }

        let openRing = ring.first == ring.last ? Array(ring.dropLast()) : ring
        guard openRing.count >= 3 else { return nil }

        let center = projectedCenter(for: [ring])
        let metersPerLat = 111_320.0
        let metersPerLon = max(cos(center.lat * .pi / 180.0) * metersPerLat, 0.0001)
        let projectedPoints = openRing.map { point in
            ProjectedPoint(
                x: (point[0] - center.lon) * metersPerLon,
                y: (point[1] - center.lat) * metersPerLat
            )
        }

        let centroidX = projectedPoints.map(\.x).reduce(0, +) / Double(projectedPoints.count)
        let centroidY = projectedPoints.map(\.y).reduce(0, +) / Double(projectedPoints.count)

        var insetRing: [[Double]] = []
        insetRing.reserveCapacity(openRing.count + 1)

        for point in projectedPoints {
            let dx = centroidX - point.x
            let dy = centroidY - point.y
            let distance = hypot(dx, dy)
            guard distance.isFinite, distance > 0.001 else { return nil }

            let offset = min(insetMeters, distance * 0.35)
            let unitX = dx / distance
            let unitY = dy / distance
            let insetX = point.x + unitX * offset
            let insetY = point.y + unitY * offset
            insetRing.append([
                center.lon + insetX / metersPerLon,
                center.lat + insetY / metersPerLat
            ])
        }

        guard insetRing.count >= 3 else { return nil }
        insetRing.append(insetRing[0])
        return insetRing
    }

    private static func centroidCoordinate(for polygons: [[[Double]]]) -> CLLocationCoordinate2D? {
        var weightedLongitude = 0.0
        var weightedLatitude = 0.0
        var totalWeight = 0.0
        var fallbackPoints: [[Double]] = []

        for polygon in polygons {
            let openRing = polygon.first == polygon.last ? Array(polygon.dropLast()) : polygon
            guard openRing.count >= 3 else { continue }

            fallbackPoints.append(contentsOf: openRing)

            var signedDoubleArea = 0.0
            var centroidLongitudeTimesSixArea = 0.0
            var centroidLatitudeTimesSixArea = 0.0

            for index in openRing.indices {
                let current = openRing[index]
                let next = openRing[(index + 1) % openRing.count]
                guard current.count >= 2, next.count >= 2 else { continue }

                let cross = (current[0] * next[1]) - (next[0] * current[1])
                signedDoubleArea += cross
                centroidLongitudeTimesSixArea += (current[0] + next[0]) * cross
                centroidLatitudeTimesSixArea += (current[1] + next[1]) * cross
            }

            let signedArea = signedDoubleArea / 2.0
            guard abs(signedArea) > 0.000000001 else { continue }

            let centroidLongitude = centroidLongitudeTimesSixArea / (6.0 * signedArea)
            let centroidLatitude = centroidLatitudeTimesSixArea / (6.0 * signedArea)
            let weight = abs(signedArea)

            guard centroidLongitude.isFinite, centroidLatitude.isFinite else { continue }
            weightedLongitude += centroidLongitude * weight
            weightedLatitude += centroidLatitude * weight
            totalWeight += weight
        }

        if totalWeight > 0 {
            return CLLocationCoordinate2D(
                latitude: weightedLatitude / totalWeight,
                longitude: weightedLongitude / totalWeight
            )
        }

        guard !fallbackPoints.isEmpty else { return nil }
        let averageLongitude = fallbackPoints.map { $0[0] }.reduce(0, +) / Double(fallbackPoints.count)
        let averageLatitude = fallbackPoints.map { $0[1] }.reduce(0, +) / Double(fallbackPoints.count)
        guard averageLongitude.isFinite, averageLatitude.isFinite else { return nil }
        return CLLocationCoordinate2D(latitude: averageLatitude, longitude: averageLongitude)
    }

    private static func projectedCenter(for polygons: [[[Double]]]) -> (lon: Double, lat: Double) {
        let points = polygons.flatMap { $0 }
        let lon = points.map { $0[0] }.reduce(0, +) / Double(max(points.count, 1))
        let lat = points.map { $0[1] }.reduce(0, +) / Double(max(points.count, 1))
        return (lon, lat)
    }

    private static func principalAxisAngle(for points: [ProjectedPoint]) -> Double {
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)

        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for point in points {
            let dx = point.x - meanX
            let dy = point.y - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        return 0.5 * atan2(2 * sxy, sxx - syy)
    }

    private static func clipPolygon(_ polygon: [RotatedPoint], minU: Double, maxU: Double) -> [RotatedPoint] {
        let afterMin = clipAgainstBoundary(
            polygon,
            isInside: { $0.u >= minU },
            intersection: { previous, current in
                intersect(previous: previous, current: current, boundaryU: minU)
            }
        )
        return clipAgainstBoundary(
            afterMin,
            isInside: { $0.u <= maxU },
            intersection: { previous, current in
                intersect(previous: previous, current: current, boundaryU: maxU)
            }
        )
    }

    private static func clipAgainstBoundary(
        _ polygon: [RotatedPoint],
        isInside: (RotatedPoint) -> Bool,
        intersection: (RotatedPoint, RotatedPoint) -> RotatedPoint
    ) -> [RotatedPoint] {
        guard !polygon.isEmpty else { return [] }

        var output: [RotatedPoint] = []
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            let previousInside = isInside(previous)
            let currentInside = isInside(current)

            if currentInside {
                if !previousInside {
                    output.append(intersection(previous, current))
                }
                output.append(current)
            } else if previousInside {
                output.append(intersection(previous, current))
            }

            previous = current
        }

        return removeAdjacentDuplicatePoints(output)
    }

    private static func intersect(previous: RotatedPoint, current: RotatedPoint, boundaryU: Double) -> RotatedPoint {
        let deltaU = current.u - previous.u
        guard abs(deltaU) > 0.000001 else {
            return RotatedPoint(u: boundaryU, v: current.v)
        }

        let t = (boundaryU - previous.u) / deltaU
        return RotatedPoint(
            u: boundaryU,
            v: previous.v + (current.v - previous.v) * t
        )
    }

    private static func removeAdjacentDuplicatePoints(_ points: [RotatedPoint]) -> [RotatedPoint] {
        var cleaned: [RotatedPoint] = []
        for point in points {
            if let last = cleaned.last,
               abs(last.u - point.u) < 0.000001,
               abs(last.v - point.v) < 0.000001 {
                continue
            }
            cleaned.append(point)
        }
        return cleaned
    }
    
    // MARK: - Address Tap Result
    
    /// Result of tapping the addresses layer. Decodes from feature properties.
    struct AddressTapResult: Decodable {
        let addressId: UUID
        let formatted: String
        let gersId: String?
        let buildingGersId: String?
        let houseNumber: String?
        let streetName: String?
        let source: String?
        
        init(addressId: UUID, formatted: String, gersId: String?, buildingGersId: String?, houseNumber: String?, streetName: String?, source: String?) {
            self.addressId = addressId
            self.formatted = formatted
            self.gersId = gersId
            self.buildingGersId = buildingGersId
            self.houseNumber = houseNumber
            self.streetName = streetName
            self.source = source
        }
        
        enum CodingKeys: String, CodingKey {
            case addressId = "id"
            case addressIdAlt = "address_id"
            case formatted
            case gersId = "gers_id"
            case buildingGersId = "building_gers_id"
            case houseNumber = "house_number"
            case streetName = "street_name"
            case source
        }
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let idFromId = try c.decodeIfPresent(String.self, forKey: .addressId)
            let idFromAddressId = try c.decodeIfPresent(String.self, forKey: .addressIdAlt)
            let idString = idFromId ?? idFromAddressId ?? ""
            guard let uuid = UUID(uuidString: idString) else {
                throw DecodingError.dataCorruptedError(forKey: .addressId, in: c, debugDescription: "Invalid UUID string: \(idString)")
            }
            addressId = uuid
            formatted = try c.decodeIfPresent(String.self, forKey: .formatted) ?? ""
            gersId = try c.decodeIfPresent(String.self, forKey: .gersId)
            buildingGersId = try c.decodeIfPresent(String.self, forKey: .buildingGersId)
            houseNumber = try c.decodeIfPresent(String.self, forKey: .houseNumber)
            streetName = try c.decodeIfPresent(String.self, forKey: .streetName)
            source = try c.decodeIfPresent(String.self, forKey: .source)
        }
    }

    struct ParcelLinkedAddressTapResult {
        let addressIds: [UUID]
        let preferredAddress: AddressTapResult?
    }
    
    // MARK: - Click Handling
    
    /// Unwrap Turf JSONValue properties to [String: Any] so SafeJSON/JSONDecoder get real types (not description strings).
    private func unwrapTurfProperties(_ properties: [String: JSONValue?]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, val) in properties {
            if let j = val {
                result[key] = unwrapTurfValue(j)
            } else {
                result[key] = NSNull()
            }
        }
        return result
    }
    
    private func unwrapTurfValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .object(let o): return unwrapTurfProperties(o)
        case .array(let a): return a.map { elem in elem.map { unwrapTurfValue($0) } ?? NSNull() }
        @unknown default: return NSNull()
        }
    }
    
    /// Result of tapping either the buildings or addresses layer
    enum BuildingOrAddressTapResult {
        case building(BuildingProperties)
        case address(AddressTapResult)
    }

    func flyerProximityAddress(at coordinate: CLLocationCoordinate2D, searchMeters: Double) async -> FlyerAddress? {
        guard let mapView = mapView else { return nil }
        let point = mapView.mapboxMap.point(for: coordinate)
        let pixelRadius = flyerProximityPixelRadius(
            searchMeters: searchMeters,
            coordinate: coordinate,
            mapView: mapView
        )
        let searchBox = CGRect(
            x: point.x - pixelRadius,
            y: point.y - pixelRadius,
            width: pixelRadius * 2,
            height: pixelRadius * 2
        )

        if let address = await queryFlyerAddress(
            in: searchBox,
            layerIds: [
                VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId,
                VectorTileDiamondGeometryProvider.addressCircleLayerId,
                Self.addressHouseIconLayerId,
                Self.selectedAddressesLayerId,
                Self.addressesLayerId
            ],
            fallbackCoordinate: coordinate,
            preferFallbackCoordinate: false,
            allowRootAddressFallback: true,
            includeFeatureIdAsAddress: true
        ) {
            return address
        }

        if let buildingAddress = await queryFlyerAddress(
            in: searchBox,
            layerIds: [
                VectorTileDiamondGeometryProvider.buildingFillLayerId,
                Self.buildingsLayerId
            ],
            fallbackCoordinate: coordinate,
            preferFallbackCoordinate: false,
            allowRootAddressFallback: false,
            includeFeatureIdAsAddress: false
        ) {
            return buildingAddress
        }

        return await queryFlyerAddress(
            at: point,
            layerIds: [
                VectorTileDiamondGeometryProvider.parcelFillLayerId,
                Self.parcelsFillLayerId
            ],
            fallbackCoordinate: coordinate,
            preferFallbackCoordinate: true,
            allowRootAddressFallback: false,
            includeFeatureIdAsAddress: false
        )
    }

    private func queryFlyerAddress(
        at point: CGPoint,
        layerIds: [String],
        fallbackCoordinate: CLLocationCoordinate2D,
        preferFallbackCoordinate: Bool,
        allowRootAddressFallback: Bool,
        includeFeatureIdAsAddress: Bool
    ) async -> FlyerAddress? {
        guard let mapView = mapView else { return nil }
        let availableLayerIds = availableRenderedLayerIds(from: layerIds)
        guard !availableLayerIds.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            mapView.mapboxMap.queryRenderedFeatures(
                with: point,
                options: RenderedQueryOptions(layerIds: availableLayerIds, filter: nil)
            ) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: self.firstFlyerAddress(
                        from: result,
                        fallbackCoordinate: fallbackCoordinate,
                        preferFallbackCoordinate: preferFallbackCoordinate,
                        allowRootAddressFallback: allowRootAddressFallback,
                        includeFeatureIdAsAddress: includeFeatureIdAsAddress
                    )
                )
            }
        }
    }

    private func queryFlyerAddress(
        in box: CGRect,
        layerIds: [String],
        fallbackCoordinate: CLLocationCoordinate2D,
        preferFallbackCoordinate: Bool,
        allowRootAddressFallback: Bool,
        includeFeatureIdAsAddress: Bool
    ) async -> FlyerAddress? {
        guard let mapView = mapView else { return nil }
        let availableLayerIds = availableRenderedLayerIds(from: layerIds)
        guard !availableLayerIds.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            mapView.mapboxMap.queryRenderedFeatures(
                with: box,
                options: RenderedQueryOptions(layerIds: availableLayerIds, filter: nil)
            ) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: self.firstFlyerAddress(
                        from: result,
                        fallbackCoordinate: fallbackCoordinate,
                        preferFallbackCoordinate: preferFallbackCoordinate,
                        allowRootAddressFallback: allowRootAddressFallback,
                        includeFeatureIdAsAddress: includeFeatureIdAsAddress
                    )
                )
            }
        }
    }

    private func firstFlyerAddress(
        from result: Result<[QueriedRenderedFeature], Error>,
        fallbackCoordinate: CLLocationCoordinate2D,
        preferFallbackCoordinate: Bool,
        allowRootAddressFallback: Bool,
        includeFeatureIdAsAddress: Bool
    ) -> FlyerAddress? {
        guard case .success(let features) = result else { return nil }
        for renderedFeature in features {
            if let address = flyerAddress(
                from: renderedFeature.queriedFeature.feature,
                fallbackCoordinate: fallbackCoordinate,
                preferFallbackCoordinate: preferFallbackCoordinate,
                allowRootAddressFallback: allowRootAddressFallback,
                includeFeatureIdAsAddress: includeFeatureIdAsAddress
            ) {
                return address
            }
        }
        return nil
    }

    private func flyerAddress(
        from feature: Feature,
        fallbackCoordinate: CLLocationCoordinate2D,
        preferFallbackCoordinate: Bool,
        allowRootAddressFallback: Bool,
        includeFeatureIdAsAddress: Bool
    ) -> FlyerAddress? {
        var converted = feature.properties.map(unwrapTurfProperties) ?? [:]
        if let rootId = rootFeatureId(from: feature), !rootId.isEmpty {
            converted["id"] = converted["id"] ?? rootId
            if allowRootAddressFallback {
                converted["address_id"] = converted["address_id"] ?? rootId
            }
        }
        var identityKeys = [
            "address_id",
            "campaign_address_id",
            "campaignAddressId"
        ]
        if includeFeatureIdAsAddress {
            identityKeys.append("id")
        }
        guard let addressId = firstUUIDString(in: converted, keys: identityKeys),
              let uuid = UUID(uuidString: addressId) else {
            return nil
        }

        let coordinate = preferFallbackCoordinate
            ? fallbackCoordinate
            : (mapFeatureGeometry(from: feature).flatMap(CampaignTargetResolver.coordinate(for:)) ?? fallbackCoordinate)
        return FlyerAddress(
            id: uuid,
            formatted: flyerAddressLabel(from: converted),
            coordinate: coordinate
        )
    }

    private func availableRenderedLayerIds(from layerIds: [String]) -> [String] {
        guard let mapView = mapView else { return [] }
        let existing = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
        return layerIds.filter { existing.contains($0) }
    }

    private func flyerProximityPixelRadius(
        searchMeters: Double,
        coordinate: CLLocationCoordinate2D,
        mapView: MapView
    ) -> CGFloat {
        let clampedMeters = min(30, max(8, searchMeters))
        let latitudeDelta = clampedMeters / 111_320.0
        let nearby = CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeDelta,
            longitude: coordinate.longitude
        )
        let originPoint = mapView.mapboxMap.point(for: coordinate)
        let nearbyPoint = mapView.mapboxMap.point(for: nearby)
        let radius = hypot(originPoint.x - nearbyPoint.x, originPoint.y - nearbyPoint.y)
        guard radius.isFinite, radius > 0 else { return 24 }
        return min(56, max(12, radius))
    }

    private func firstUUIDString(in properties: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let uuid = uuidString(from: properties[key]) {
                return uuid
            }
        }
        return nil
    }

    private func uuidString(from value: Any?) -> String? {
        if let string = value as? String, let uuid = UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return uuid.uuidString.lowercased()
        }
        if let values = value as? [Any] {
            for nested in values {
                if let uuid = uuidString(from: nested) {
                    return uuid
                }
            }
        }
        return nil
    }

    private func uuidStrings(from value: Any?) -> [String] {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let uuid = UUID(uuidString: trimmed) {
                return [uuid.uuidString.lowercased()]
            }
            return trimmed
                .split { $0 == "," || $0 == " " || $0 == ";" }
                .compactMap { UUID(uuidString: String($0))?.uuidString.lowercased() }
        }
        if let values = value as? [Any] {
            var seen: Set<String> = []
            var uuids: [String] = []
            for nested in values {
                for uuid in uuidStrings(from: nested) where !seen.contains(uuid) {
                    seen.insert(uuid)
                    uuids.append(uuid)
                }
            }
            return uuids
        }
        return []
    }

    private func flyerAddressLabel(from properties: [String: Any]) -> String {
        for key in ["formatted", "address_text", "full_address", "label"] {
            if let value = properties[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        let house = (properties["house_number_label"] as? String)
            ?? (properties["house_number"] as? String)
            ?? (properties["street_number"] as? String)
        let street = (properties["street_name"] as? String)
            ?? (properties["primary_street_name"] as? String)
        let combined = "\(house ?? "") \(street ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "Address" : combined
    }

    /// Get building or address at tap location. Query direct address layers first, then buildings,
    /// then parcel fallback only when the parcel has explicit address metadata.
    func getBuildingOrAddressAt(point: CGPoint, completion: @escaping (BuildingOrAddressTapResult?) -> Void) {
        queryAddressHitbox(at: point, mode: .broad) { [weak self] address in
            guard let self else { return }
            if let address {
                completion(.address(address))
                return
            }

            self.queryBuildingTap(at: point) { [weak self] building in
                guard let self else { return }
                if let building {
                    completion(.building(building))
                    return
                }

                self.queryParcelAddressFallback(at: point) { address in
                    if let address {
                        completion(.address(address))
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Samples a small grid of points across the visible viewport to see whether any building extrusions have painted.
    func hasRenderedBuildings(completion: @escaping (Bool) -> Void) {
        guard let mapView = mapView else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let size = mapView.bounds.size
        guard size.width > 0, size.height > 0 else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let points = Self.buildingRenderProbePoints(for: size)
        queryRenderedBuildings(at: points, index: 0, completion: completion)
    }

    /// Get building at tap location (async via completion)
    func getBuildingAt(point: CGPoint, completion: @escaping (BuildingProperties?) -> Void) {
        getBuildingFeatureAt(point: point) { feature in
            completion(feature?.properties)
        }
    }

    /// Get the full building feature at tap location. PMTiles-backed buildings need the queried
    /// geometry and promoted feature id for move/delete tools because they are not in the local GeoJSON source.
    func getBuildingFeatureAt(point: CGPoint, completion: @escaping (BuildingFeature?) -> Void) {
        guard let mapView = mapView else { completion(nil); return }

        let layerIds = availableRenderedLayerIds(from: buildingTapLayerIds)
        guard !layerIds.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let options = RenderedQueryOptions(layerIds: layerIds, filter: nil)
        mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { result in
            switch result {
            case .success(let features):
                for renderedFeature in features {
                    if let feature = self.buildingFeature(from: renderedFeature.queriedFeature.feature) {
                        DispatchQueue.main.async { completion(feature) }
                        return
                    }
                }
                DispatchQueue.main.async { completion(nil) }
            case .failure(let error):
                print("❌ [MapLayer] Error querying features: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    func renderedBuildingFeatures(
        near coordinate: CLLocationCoordinate2D,
        searchMeters: Double
    ) async -> [BuildingFeature] {
        guard let mapView = mapView else { return [] }

        let point = mapView.mapboxMap.point(for: coordinate)
        let pixelRadius = renderedFeaturePixelRadius(
            searchMeters: searchMeters,
            coordinate: coordinate,
            mapView: mapView
        )
        let searchBox = CGRect(
            x: point.x - pixelRadius,
            y: point.y - pixelRadius,
            width: pixelRadius * 2,
            height: pixelRadius * 2
        )
        let layerIds = availableRenderedLayerIds(from: buildingTapLayerIds)
        guard !layerIds.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            mapView.mapboxMap.queryRenderedFeatures(
                with: searchBox,
                options: RenderedQueryOptions(layerIds: layerIds, filter: nil)
            ) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                switch result {
                case .success(let features):
                    continuation.resume(
                        returning: features.compactMap { self.buildingFeature(from: $0.queriedFeature.feature) }
                    )
                case .failure(let error):
                    print("❌ [MapLayer] Error querying nearby building features: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func renderedFeaturePixelRadius(
        searchMeters: Double,
        coordinate: CLLocationCoordinate2D,
        mapView: MapView
    ) -> CGFloat {
        let clampedMeters = min(50, max(8, searchMeters))
        let latitudeDelta = clampedMeters / 111_320.0
        let nearby = CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeDelta,
            longitude: coordinate.longitude
        )
        let originPoint = mapView.mapboxMap.point(for: coordinate)
        let nearbyPoint = mapView.mapboxMap.point(for: nearby)
        let radius = hypot(originPoint.x - nearbyPoint.x, originPoint.y - nearbyPoint.y)
        guard radius.isFinite, radius > 0 else { return 28 }
        return min(72, max(12, radius))
    }

    private func buildingFeature(from feature: Feature) -> BuildingFeature? {
        guard let properties = feature.properties,
              let geometry = mapFeatureGeometry(from: feature) else {
            return nil
        }

        var converted = unwrapTurfProperties(properties)
        if let rootId = rootFeatureId(from: feature), !rootId.isEmpty {
            if converted["id"] == nil {
                converted["id"] = rootId
            }
            if converted["address_id"] == nil,
               installedDiamondManifest?.promoteIds?.buildings == "address_id",
               UUID(uuidString: rootId) != nil {
                converted["address_id"] = rootId
            }
        }

        let sanitized = SafeJSON.sanitize(converted)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = SafeJSON.data(from: sanitized) else {
            print("❌ [MapLayer] Failed to serialize queried building properties")
            return nil
        }

        do {
            let building = try JSONDecoder().decode(BuildingProperties.self, from: data)
            return BuildingFeature(
                type: "Feature",
                id: rootFeatureId(from: feature),
                geometry: geometry,
                properties: building
            )
        } catch {
            print("❌ [MapLayer] Failed to decode BuildingProperties: \(error)")
            print("🔍 [MapLayer] JSON data: \(String(data: data, encoding: .utf8) ?? "invalid UTF-8")")
            return nil
        }
    }

    private func rootFeatureId(from feature: Feature) -> String? {
        guard let object = encodedFeatureDictionary(feature),
              let rawId = object["id"] else {
            return nil
        }
        if let stringId = rawId as? String {
            return stringId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let numberId = rawId as? NSNumber {
            return numberId.stringValue
        }
        return nil
    }

    private func mapFeatureGeometry(from feature: Feature) -> MapFeatureGeoJSONGeometry? {
        guard let object = encodedFeatureDictionary(feature),
              let geometry = object["geometry"] as? [String: Any],
              JSONSerialization.isValidJSONObject(geometry),
              let data = try? JSONSerialization.data(withJSONObject: geometry) else {
            return nil
        }
        return try? JSONDecoder().decode(MapFeatureGeoJSONGeometry.self, from: data)
    }

    private func encodedFeatureDictionary(_ feature: Feature) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(feature),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func queryRenderedBuildings(
        at points: [CGPoint],
        index: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard let mapView = mapView else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        guard index < points.count else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let options = RenderedQueryOptions(
            layerIds: [
                VectorTileDiamondGeometryProvider.buildingFillLayerId,
                Self.buildingsLayerId,
                Self.townhomeOverlayLayerId,
                Self.townhomeSliceOutlineLayerId,
                Self.townhomeDividerLayerId,
                Self.townhomeDividerStripLayerId,
                Self.townhomeOutlineLayerId
            ],
            filter: nil
        )

        mapView.mapboxMap.queryRenderedFeatures(with: points[index], options: options) { [weak self] result in
            switch result {
            case .success(let features):
                if !features.isEmpty {
                    DispatchQueue.main.async { completion(true) }
                } else {
                    self?.queryRenderedBuildings(at: points, index: index + 1, completion: completion)
                        ?? DispatchQueue.main.async { completion(false) }
                }
            case .failure:
                self?.queryRenderedBuildings(at: points, index: index + 1, completion: completion)
                    ?? DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private static func buildingRenderProbePoints(for size: CGSize) -> [CGPoint] {
        let horizontalFractions: [CGFloat] = [0.18, 0.35, 0.5, 0.65, 0.82]
        let verticalFractions: [CGFloat] = [0.2, 0.38, 0.56, 0.74]

        return verticalFractions.flatMap { yFraction in
            horizontalFractions.map { xFraction in
                CGPoint(x: size.width * xFraction, y: size.height * yFraction)
            }
        }
    }
    
    /// Get address at tap location (async via completion). Use when display mode is Addresses.
    func getAddressAt(point: CGPoint, completion: @escaping (AddressTapResult?) -> Void) {
        queryAddressHitbox(at: point, mode: .broad, completion: completion)
    }

    /// Smaller address target for building mode so building geometry wins unless the user taps
    /// directly on an address dot/number.
    func getStrictAddressAt(point: CGPoint, completion: @escaping (AddressTapResult?) -> Void) {
        queryAddressHitbox(at: point, mode: .strict, completion: completion)
    }

    func getParcelLinkedAddressAt(point: CGPoint, completion: @escaping (AddressTapResult?) -> Void) {
        queryParcelAddressFallback(at: point, completion: completion)
    }

    func getParcelLinkedAddressesAt(point: CGPoint, completion: @escaping (ParcelLinkedAddressTapResult?) -> Void) {
        queryParcelLinkedAddressesFallback(at: point, completion: completion)
    }

    private enum AddressHitMode {
        case strict
        case broad

        var radius: CGFloat {
            switch self {
            case .strict: return 12
            case .broad: return 22
            }
        }
    }

    private var strictAddressTapLayerIds: [String] {
        [
            VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId,
            VectorTileDiamondGeometryProvider.addressCircleLayerId,
            VectorTileDiamondGeometryProvider.addressNumberLayerId,
            Self.addressNumbersLayerId,
            Self.addressHouseIconLayerId,
            Self.selectedAddressesLayerId,
            Self.addressesLayerId
        ]
    }

    private var broadAddressTapLayerIds: [String] {
        [
            VectorTileDiamondGeometryProvider.selectedAddressCircleLayerId,
            VectorTileDiamondGeometryProvider.addressCircleLayerId,
            VectorTileDiamondGeometryProvider.addressNumberLayerId,
            Self.addressLabelHitboxLayerId,
            Self.addressNumbersLayerId,
            Self.addressHouseIconLayerId,
            Self.selectedAddressesLayerId,
            Self.addressesLayerId
        ]
    }

    private var buildingTapLayerIds: [String] {
        [
            Self.townhomeOverlayLayerId,
            Self.townhomeSliceOutlineLayerId,
            Self.townhomeDividerStripLayerId,
            Self.townhomeDividerLayerId,
            Self.townhomeOutlineLayerId,
            VectorTileDiamondGeometryProvider.buildingFillLayerId,
            Self.buildingsLayerId
        ]
    }

    private func queryAddressHitbox(
        at point: CGPoint,
        mode: AddressHitMode,
        completion: @escaping (AddressTapResult?) -> Void
    ) {
        guard let mapView = mapView else { completion(nil); return }

        let requestedLayerIds: [String] = {
            switch mode {
            case .strict: return strictAddressTapLayerIds
            case .broad: return broadAddressTapLayerIds
            }
        }()
        let layerIds = availableRenderedLayerIds(from: requestedLayerIds)
        guard !layerIds.isEmpty else {
            completion(nil)
            return
        }
        let radius = mode.radius
        let hitbox = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let options = RenderedQueryOptions(layerIds: layerIds, filter: nil)
        mapView.mapboxMap.queryRenderedFeatures(with: hitbox, options: options) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let features):
                for renderedFeature in features {
                    if let address = self.addressTapResult(from: renderedFeature.queriedFeature.feature) {
                        DispatchQueue.main.async { completion(address) }
                        return
                    }
                }
                DispatchQueue.main.async { completion(nil) }
            case .failure(let error):
                print("❌ [MapLayer] Error querying address features: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func addressTapResult(from feature: Feature) -> AddressTapResult? {
        guard let data = decodedFeaturePropertiesData(from: feature, includeRootAddressFallback: true) else {
            return nil
        }
        return try? JSONDecoder().decode(AddressTapResult.self, from: data)
    }

    private func buildingProperties(from feature: Feature) -> BuildingProperties? {
        guard let data = decodedFeaturePropertiesData(from: feature, includeRootAddressFallback: false) else {
            return nil
        }
        return try? JSONDecoder().decode(BuildingProperties.self, from: data)
    }

    private func decodedFeaturePropertiesData(
        from feature: Feature,
        includeRootAddressFallback: Bool
    ) -> Data? {
        guard let properties = feature.properties else {
            return nil
        }
        var converted = unwrapTurfProperties(properties)
        if let rootId = rootFeatureId(from: feature), !rootId.isEmpty {
            converted["id"] = converted["id"] ?? rootId
            if includeRootAddressFallback {
                converted["address_id"] = converted["address_id"] ?? rootId
            }
        }
        let sanitized = SafeJSON.sanitize(converted)
        guard JSONSerialization.isValidJSONObject(sanitized) else {
            return nil
        }
        return SafeJSON.data(from: sanitized)
    }

    private func queryBuildingTap(at point: CGPoint, completion: @escaping (BuildingProperties?) -> Void) {
        getBuildingFeatureAt(point: point) { feature in
            completion(feature?.properties)
        }
    }

    private func queryParcelAddressFallback(at point: CGPoint, completion: @escaping (AddressTapResult?) -> Void) {
        queryParcelLinkedAddressesFallback(at: point) { result in
            completion(result?.preferredAddress)
        }
    }

    private func queryParcelLinkedAddressesFallback(
        at point: CGPoint,
        completion: @escaping (ParcelLinkedAddressTapResult?) -> Void
    ) {
        guard let mapView = mapView else { completion(nil); return }

        let layerIds = availableRenderedLayerIds(from: [
            VectorTileDiamondGeometryProvider.parcelFillLayerId,
            Self.parcelsFillLayerId
        ])
        guard !layerIds.isEmpty else {
            completion(nil)
            return
        }

        mapView.mapboxMap.queryRenderedFeatures(
            with: point,
            options: RenderedQueryOptions(layerIds: layerIds, filter: nil)
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let features):
                for renderedFeature in features {
                    if let result = self.parcelLinkedAddressTapResult(from: renderedFeature.queriedFeature.feature) {
                        DispatchQueue.main.async { completion(result) }
                        return
                    }
                }
                DispatchQueue.main.async { completion(nil) }
            case .failure(let error):
                print("❌ [MapLayer] Error querying parcel fallback features: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func parcelAddressTapResult(from feature: Feature) -> AddressTapResult? {
        parcelLinkedAddressTapResult(from: feature)?.preferredAddress
    }

    private func parcelLinkedAddressTapResult(from feature: Feature) -> ParcelLinkedAddressTapResult? {
        guard let properties = feature.properties else { return nil }
        let converted = unwrapTurfProperties(properties)

        let primaryAddressId = firstUUIDString(in: converted, keys: [
            "address_id",
            "campaign_address_id",
            "campaignAddressId"
        ])
        let rawAddressIds = [primaryAddressId].compactMap { $0 } + uuidStrings(from: converted["address_ids"])
        var seen = Set<UUID>()
        let addressIds = rawAddressIds.compactMap { UUID(uuidString: $0) }.filter { seen.insert($0).inserted }
        guard !addressIds.isEmpty else { return nil }

        let preferredId: UUID?
        if let primaryAddressId, let primaryUUID = UUID(uuidString: primaryAddressId) {
            preferredId = primaryUUID
        } else if addressIds.count == 1 {
            preferredId = addressIds[0]
        } else {
            preferredId = nil
        }

        let preferredAddress = preferredId.map {
            AddressTapResult(
                addressId: $0,
                formatted: flyerAddressLabel(from: converted),
                gersId: converted["gers_id"] as? String,
                buildingGersId: converted["building_gers_id"] as? String,
                houseNumber: converted["house_number"] as? String,
                streetName: converted["street_name"] as? String,
                source: converted["source"] as? String
            )
        }

        return ParcelLinkedAddressTapResult(addressIds: addressIds, preferredAddress: preferredAddress)
    }
    
    // MARK: - Cleanup
    
    /// Remove all layers and sources
    func cleanup() {
        guard let mapView = mapView else { return }
        
        // Remove layers
        try? mapView.mapboxMap.removeLayer(withId: Self.buildingsSelectedGlowLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.buildingsLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.buildingsLeadGlowLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeDividerLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeDividerStripLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeSliceOutlineLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeOutlineLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeOverlayLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeLeadGlowLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.selectedAddressesLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressesLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressesLeadGlowLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressHouseIconLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressLabelHitboxLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressNumbersLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.manualAddressPreviewLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.teammatePresenceCircleLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.teammatePresenceLabelLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.parcelsLineLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.parcelsFillLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.roadsLayerId)
        
        // Remove sources
        try? mapView.mapboxMap.removeSource(withId: Self.buildingsSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.townhomeOverlaySourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.addressesSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.addressNumbersSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.manualAddressPreviewSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.teammatePresenceSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.parcelsSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.roadsSourceId)
        
        print("✅ [MapLayer] Cleaned up all layers and sources")
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
