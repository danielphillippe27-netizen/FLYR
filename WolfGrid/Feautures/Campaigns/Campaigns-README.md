# Campaigns Feature

## Overview
The Campaigns feature is the core functionality of FLYR, managing flyer distribution campaigns, tracking performance, and providing analytics.

## Components

### CampaignDetailView.swift
- **Purpose**: Detailed view of individual campaign performance
- **Features**:
  - Campaign title and description display
  - Performance metrics (total flyers, scans, conversions)
  - Regional information
  - Visual statistics dashboard

### CampaignsAPI.swift
- **Purpose**: Backend integration for campaign data management
- **Features**:
  - Fetch all campaigns from Supabase
  - Retrieve individual campaign details
  - Real-time data synchronization
  - Error handling and data validation

### CampaignsHooks.swift
- **Purpose**: State management for campaign data
- **Features**:
  - Observable campaign state
  - Loading states and error handling
  - Async data operations
  - Reactive UI updates

### CampaignsListView.swift
- **Purpose**: List view of all campaigns
- **Features**:
  - Campaign overview display
  - Navigation to campaign details
  - Filtering and sorting options
  - Campaign management actions

## Data Model

### Campaign.swift (Shared Model)
```swift
struct Campaign: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let description: String
    let coverImageURL: String
    let totalFlyers: Int
    let scans: Int
    let conversions: Int
    let region: String?
}
```

## Key Features
- **Campaign Creation**: Set up new flyer distribution campaigns
- **Performance Tracking**: Monitor scans, conversions, and engagement
- **Regional Management**: Organize campaigns by geographic areas
- **Analytics Dashboard**: Visual representation of campaign metrics
- **Real-time Updates**: Live data synchronization with backend

## Backend Integration
- **Supabase Database**: Campaign data storage and retrieval
- **Real-time Sync**: Live updates across devices
- **User Authentication**: Secure campaign access
- **Data Validation**: Ensure data integrity

## Future Enhancements
- **Advanced Analytics**: Detailed performance insights
- **A/B Testing**: Campaign variant testing
- **Team Collaboration**: Multi-user campaign management
- **Automated Reporting**: Scheduled performance reports
- **Integration APIs**: Third-party service connections

## Dependencies
- SwiftUI for UI components
- Supabase for backend services
- Foundation for data structures
- Combine for reactive programming
