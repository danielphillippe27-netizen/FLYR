import UIKit

/// Popup view showing building and address information
final class BuildingPopupView: UIView {
    
    // MARK: - UI Components
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let addressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let scansLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let matchQualityLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let buildingInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties
    
    private var onClose: (() -> Void)?
    private var onAction: (() -> Void)?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.3)
        
        addSubview(containerView)
        containerView.addSubview(closeButton)
        containerView.addSubview(addressLabel)
        containerView.addSubview(statusView)
        statusView.addSubview(statusLabel)
        containerView.addSubview(scansLabel)
        containerView.addSubview(matchQualityLabel)
        containerView.addSubview(buildingInfoLabel)
        containerView.addSubview(actionButton)
        
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            
            addressLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            addressLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            addressLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            
            statusView.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 12),
            statusView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusView.heightAnchor.constraint(equalToConstant: 28),
            
            statusLabel.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            
            scansLabel.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            scansLabel.leadingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: 12),
            
            matchQualityLabel.topAnchor.constraint(equalTo: statusView.bottomAnchor, constant: 8),
            matchQualityLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            matchQualityLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            buildingInfoLabel.topAnchor.constraint(equalTo: matchQualityLabel.bottomAnchor, constant: 4),
            buildingInfoLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            buildingInfoLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            actionButton.topAnchor.constraint(equalTo: buildingInfoLabel.bottomAnchor, constant: 16),
            actionButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            actionButton.heightAnchor.constraint(equalToConstant: 48),
            actionButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
        
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Configure
    
    func configure(
        with buildingData: BuildingWithAddress,
        onClose: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.onAction = onAction
        
        // Address
        if let address = buildingData.address {
            addressLabel.text = address.address
            addressLabel.textColor = .label
        } else {
            addressLabel.text = "Orphan Building (No Address)"
            addressLabel.textColor = .secondaryLabel
        }
        
        // Status
        let status = buildingData.stats?.status ?? "not_visited"
        let scans = buildingData.stats?.scansTotal ?? 0
        configureStatus(status: status, scans: scans)
        
        // Match quality
        if let link = buildingData.link {
            matchQualityLabel.text = "Match: \(formatMatchType(link.matchType)) (\(Int(link.confidence * 100))%)"
        } else {
            matchQualityLabel.text = "No link data"
        }
        
        // Building info
        var infoParts: [String] = []
        let height = buildingData.building.properties.heightM ?? buildingData.building.properties.height
        infoParts.append("Height: \(String(format: "%.1f", height))m")
        if buildingData.building.properties.unitsCount > 1 {
            infoParts.append("Units: \(buildingData.building.properties.unitsCount)")
        }
        infoParts.append("GERS: \((buildingData.building.id ?? "").prefix(8))...")
        buildingInfoLabel.text = infoParts.joined(separator: " • ")
        
        // Action button
        if let address = buildingData.address {
            let isVisited = address.id.uuidString == (buildingData.building.properties.addressId ?? "")
            actionButton.setTitle(isVisited ? "View Details" : "Mark Visited", for: .normal)
            actionButton.backgroundColor = isVisited ? .systemGreen : .systemBlue
            actionButton.isEnabled = true
        } else {
            actionButton.setTitle("No Address Linked", for: .normal)
            actionButton.backgroundColor = .systemGray
            actionButton.isEnabled = false
        }
    }
    
    private func configureStatus(status: String, scans: Int) {
        var statusText: String
        var statusColor: UIColor
        
        if scans > 0 {
            statusText = "📱 QR Scanned (\(scans))"
            statusColor = UIColor(hex: "#8b5cf6")! // Purple
        } else {
            switch status {
            case "hot":
                statusText = "🔥 Hot Lead"
                statusColor = UIColor(hex: "#3b82f6")! // Blue
            case "visited":
                statusText = "✅ Visited"
                statusColor = UIColor(hex: "#22c55e")! // Green
            default:
                statusText = "⚪ Not Visited"
                statusColor = UIColor(hex: "#ef4444")! // Red
            }
        }
        
        statusLabel.text = statusText
        statusView.backgroundColor = statusColor
        scansLabel.text = scans > 0 ? "\(scans) scan\(scans == 1 ? "" : "s")" : ""
    }
    
    private func formatMatchType(_ type: String) -> String {
        switch type {
        case "containment_verified": return "Exact Match"
        case "containment_suspect": return "Street Mismatch"
        case "point_on_surface": return "On Boundary"
        case "proximity_verified": return "Nearby + Street"
        case "proximity_fallback": return "Nearby"
        case "manual": return "Manual"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    // MARK: - Actions
    
    @objc private func closeTapped() {
        onClose?()
    }
    
    @objc private func actionTapped() {
        onAction?()
    }
    
    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        if !containerView.frame.contains(location) {
            onClose?()
        }
    }
}

// UIColor(hex:) is defined in MapLayerManager.swift; use UIColor(hex: "#...")! at call sites.
