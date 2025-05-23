//
//  GeoFence.swift
//  Fleetly
//
//  Created by Pinaka on 06/05/25.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseFirestore

// MARK: - Utility Functions
struct CoordinateUtils {
    static func metersPerDegreeLatitude() -> Double {
        return 111_000.0 // Approximate meters per degree latitude
    }
    
    static func metersPerDegreeLongitude(atLatitude latitude: Double) -> Double {
        return 111_000.0 * cos(latitude * .pi / 180.0)
    }
    
    static func areCoordinatesEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Codable Coordinate
struct CodableCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    static func == (lhs: CodableCoordinate, rhs: CodableCoordinate) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - CLLocationCoordinate2D Extension
extension CLLocationCoordinate2D {
    var isValid: Bool {
        return !latitude.isNaN && !longitude.isNaN && latitude.isFinite && longitude.isFinite
    }
}

// MARK: - FourWheeler Model
struct FourWheeler: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var currentLocationCoordinate: CodableCoordinate?
    var assignedRouteId: UUID?
    var status: FourWheelerStatus
    var lastUpdated: Date
    var deviation: Double?
    
    enum FourWheelerStatus: String, Codable {
        case onRoute = "On Route"
        case offRoute = "Off Route"
        case unknown = "Unknown"
        
        var color: Color {
            switch self {
            case .onRoute: return .green
            case .offRoute: return .red
            case .unknown: return .gray
            }
        }
    }
    
    var currentLocation: CLLocationCoordinate2D? {
        get { currentLocationCoordinate?.coordinate }
        set { currentLocationCoordinate = newValue.map { CodableCoordinate(coordinate: $0) } }
    }
    
    static func == (lhs: FourWheeler, rhs: FourWheeler) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Route Model
struct Route: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var waypoints: [Waypoint]
    var corridorWidth: Double
    var assignedFourWheelerIds: [UUID]
    var distance: Double?
    var polylineCoordinates: [CodableCoordinate]?
    var colorData: Data
    
    var color: Color {
        get {
            if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                return Color(uiColor)
            }
            return .blue
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(newValue), requiringSecureCoding: false) {
                colorData = data
            }
        }
    }
    
    init(id: UUID = UUID(), name: String, waypoints: [Waypoint], corridorWidth: Double, assignedFourWheelerIds: [UUID], distance: Double? = nil, polylineCoordinates: [CodableCoordinate]? = nil, color: Color) {
        self.id = id
        self.name = name
        self.waypoints = waypoints
        self.corridorWidth = corridorWidth
        self.assignedFourWheelerIds = assignedFourWheelerIds
        self.distance = distance
        self.polylineCoordinates = polylineCoordinates
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(color), requiringSecureCoding: false) {
            self.colorData = data
        } else {
            self.colorData = Data()
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, waypoints, corridorWidth, assignedFourWheelerIds, distance, polylineCoordinates, colorData
    }
    
    static func == (lhs: Route, rhs: Route) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Waypoint Model
struct Waypoint: Identifiable, Codable, Equatable {
    var id: UUID
    var coordinate: CodableCoordinate
    var order: Int
    var locationName: String
    
    var locationCoordinate: CLLocationCoordinate2D {
        coordinate.coordinate
    }
    
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, order: Int, locationName: String = "") {
        self.id = id
        self.coordinate = CodableCoordinate(coordinate: coordinate)
        self.order = order
        self.locationName = locationName
    }
    
    static func == (lhs: Waypoint, rhs: Waypoint) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Improved Geofence Corridor Overlay
class GeofenceCorridorOverlay: NSObject, MKOverlay {
    let routeId: UUID
    let corridorWidth: Double
    let color: UIColor
    let polygon: MKPolygon
    
    var coordinate: CLLocationCoordinate2D {
        return polygon.coordinate
    }
    
    var boundingMapRect: MKMapRect {
        return polygon.boundingMapRect
    }
    
    init(routeId: UUID, polylineCoordinates: [CLLocationCoordinate2D], corridorWidth: Double, color: UIColor) {
        self.routeId = routeId
        self.corridorWidth = corridorWidth
        self.color = color
        
        let validCoordinates = polylineCoordinates.filter { $0.isValid }
        
        let corridorPoints = GeofenceCorridorOverlay.generateImprovedCorridor(
            route: validCoordinates,
            width: corridorWidth
        )
        
        self.polygon = MKPolygon(coordinates: corridorPoints, count: corridorPoints.count)
        
        super.init()
    }
    
    static func generateImprovedCorridor(route: [CLLocationCoordinate2D], width: Double) -> [CLLocationCoordinate2D] {
        guard route.count >= 2 else { return [] }
        
        let avgLat = route.reduce(0) { $0 + $1.latitude } / Double(route.count)
        let metersToLatDegrees = 1.0 / CoordinateUtils.metersPerDegreeLatitude()
        let metersToLonDegrees = 1.0 / CoordinateUtils.metersPerDegreeLongitude(atLatitude: avgLat)
        
        let halfWidthLat = (width / 2.0) * metersToLatDegrees
        let halfWidthLon = (width / 2.0) * metersToLonDegrees
        
        var leftSide: [CLLocationCoordinate2D] = []
        var rightSide: [CLLocationCoordinate2D] = []
        
        for i in 0..<route.count-1 {
            let p1 = route[i]
            let p2 = route[i+1]
            
            let dx = p2.longitude - p1.longitude
            let dy = p2.latitude - p1.latitude
            let length = sqrt(dx*dx + dy*dy)
            
            if length < 1e-6 { continue }
            
            let perpX = -dy / length
            let perpY = dx / length
            
            let offsetLat = perpY * halfWidthLat
            let offsetLon = perpX * halfWidthLon
            
            let leftPoint1 = CLLocationCoordinate2D(
                latitude: p1.latitude + offsetLat,
                longitude: p1.longitude + offsetLon
            )
            let rightPoint1 = CLLocationCoordinate2D(
                latitude: p1.latitude - offsetLat,
                longitude: p1.longitude - offsetLon
            )
            
            if i == 0 {
                leftSide.append(leftPoint1)
                rightSide.append(rightPoint1)
            }
            
            if i == route.count - 2 {
                let leftPoint2 = CLLocationCoordinate2D(
                    latitude: p2.latitude + offsetLat,
                    longitude: p2.longitude + offsetLon
                )
                let rightPoint2 = CLLocationCoordinate2D(
                    latitude: p2.latitude - offsetLat,
                    longitude: p2.longitude - offsetLon
                )
                leftSide.append(leftPoint2)
                rightSide.append(rightPoint2)
            }
            
            if i < route.count - 2 {
                let p3 = route[i+2]
                
                let dx2 = p3.longitude - p2.longitude
                let dy2 = p3.latitude - p2.latitude
                let length2 = sqrt(dx2*dx2 + dy2*dy2)
                
                if length2 > 1e-6 {
                    let perpX2 = -dy2 / length2
                    let perpY2 = dx2 / length2
                    
                    let offsetLat2 = perpY2 * halfWidthLat
                    let offsetLon2 = perpX2 * halfWidthLon
                    
                    let avgOffsetLat = (offsetLat + offsetLat2) / 2
                    let avgOffsetLon = (offsetLon + offsetLon2) / 2
                    
                    let leftJunction = CLLocationCoordinate2D(
                        latitude: p2.latitude + avgOffsetLat,
                        longitude: p2.longitude + avgOffsetLon
                    )
                    let rightJunction = CLLocationCoordinate2D(
                        latitude: p2.latitude - avgOffsetLat,
                        longitude: p2.longitude - avgOffsetLon
                    )
                    
                    leftSide.append(leftJunction)
                    rightSide.append(rightJunction)
                }
            }
        }
        
        var corridorPoints = leftSide
        corridorPoints.append(contentsOf: rightSide.reversed())
        
        if let first = corridorPoints.first {
            corridorPoints.append(first)
        }
        
        return corridorPoints.filter { $0.isValid }
    }
    
    static func perpendicularDistance(point: CLLocationCoordinate2D, lineStart: CLLocationCoordinate2D, lineEnd: CLLocationCoordinate2D) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        
        let lenSq = dx * dx + dy * dy
        
        if lenSq < 1e-10 {
            let deltaLat = point.latitude - lineStart.latitude
            let deltaLon = point.longitude - lineStart.longitude
            return sqrt(deltaLat * deltaLat + deltaLon * deltaLon)
        }
        
        let t = ((point.longitude - lineStart.longitude) * dx +
                (point.latitude - lineStart.latitude) * dy) / lenSq
        
        let tClamped = max(0, min(1, t))
        
        let closestX = lineStart.longitude + tClamped * dx
        let closestY = lineStart.latitude + tClamped * dy
        
        let deltaX = point.longitude - closestX
        let deltaY = point.latitude - closestY
        
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}

// MARK: - Location Manager Delegate
class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    weak var pathManager: FourWheelerPathManager?
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            pathManager?.handleAuthorizationChange(manager.authorizationStatus)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            pathManager?.handleLocationUpdate(locations)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            pathManager?.handleLocationError(error)
        }
    }
}

// MARK: - FourWheeler Path Manager
@MainActor
class FourWheelerPathManager: NSObject, ObservableObject {
    @Published var fourWheelers: [FourWheeler] = []
    @Published var routes: [Route] = []
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var activeRoutePolylines: [UUID: MKPolyline] = [:]
    @Published var activeGeofenceOverlays: [UUID: GeofenceCorridorOverlay] = [:]
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var showLocationPermissionAlert = false
    @Published var isMonitoringStarted = false
    @Published var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
        span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
    )
    
    private let locationManager = CLLocationManager()
    private let locationDelegate = LocationManagerDelegate()
    private var cancellables = Set<AnyCancellable>()
    private let routeColors: [Color] = [.blue, .red, .green, .purple]
    private var simulatedFourWheelerId: UUID?
    private var notificationStatusByFourWheeler: [UUID: Bool] = [:]
    private var simulationTimer: Timer?
    private var lastUpdateTime: Date?
    public var lastOffRouteFourWheelerId: UUID?
    private var startTime: Date?
    private var hasFourWheeler3Deviated = false
    
    static let shared = FourWheelerPathManager()
    
    private override init() {
        super.init()
        
        locationManager.delegate = locationDelegate
        locationDelegate.pathManager = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationAuthorizationStatus = locationManager.authorizationStatus
        
        requestLocationPermission()
        requestNotificationPermission()
        
        Task {
            await initializeHardcodedData()
        }
    }
    
    func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            showLocationPermissionAlert = true
        } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
    }
    
    func sendOffRouteNotification(for fourWheeler: FourWheeler) {
        let fourWheelerId = fourWheeler.id
        guard notificationStatusByFourWheeler[fourWheelerId] != true else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "FourWheeler Off Route"
        content.body = "\(fourWheeler.name) is off its assigned route! Deviation: \(fourWheeler.deviation?.formatted() ?? "N/A") meters"
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            } else {
                print("Off-route notification sent for \(fourWheeler.name)")
            }
        }
        notificationStatusByFourWheeler[fourWheelerId] = true
        lastOffRouteFourWheelerId = fourWheelerId
    }
    
    func resetNotificationFlag(for fourWheelerId: UUID) {
        notificationStatusByFourWheeler[fourWheelerId] = false
        if lastOffRouteFourWheelerId == fourWheelerId {
            lastOffRouteFourWheelerId = nil
        }
    }
    
    func centerMapOnUserLocation() {
        guard let userLocation = userLocation, userLocation.isValid else {
            let southIndiaRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
            )
            withAnimation(.easeInOut) {
                mapRegion = southIndiaRegion
            }
            return
        }
        
        let region = MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        withAnimation(.easeInOut) {
            mapRegion = region
        }
    }
    
    func centerMapOnFourWheeler(_ fourWheeler: FourWheeler) {
        guard let fourWheelerLocation = fourWheeler.currentLocation, fourWheelerLocation.isValid else {
            let defaultRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 12.2958, longitude: 76.6394),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            withAnimation(.easeInOut) {
                mapRegion = defaultRegion
            }
            return
        }
        
        let region = MKCoordinateRegion(
            center: fourWheelerLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        withAnimation(.easeInOut) {
            mapRegion = region
        }
    }
    
    func fitMapToRoutes() {
        let allCoordinates = routes.compactMap { $0.polylineCoordinates?.map { $0.coordinate } }.flatMap { $0 } +
                            fourWheelers.compactMap { $0.currentLocation }
        
        guard !allCoordinates.isEmpty else {
            let southIndiaRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
            )
            withAnimation(.easeInOut) {
                mapRegion = southIndiaRegion
            }
            return
        }
        
        let latitudes = allCoordinates.map { $0.latitude }
        let longitudes = allCoordinates.map { $0.longitude }
        
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = max((maxLat - minLat) * 1.5, 0.5)
        let spanLon = max((maxLon - minLon) * 1.5, 0.5)
        
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
        withAnimation(.easeInOut) {
            mapRegion = region
        }
    }
    
    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        locationAuthorizationStatus = status
        
        switch status {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .restricted, .denied:
            showLocationPermissionAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            
            #if targetEnvironment(simulator)
            userLocation = CLLocationCoordinate2D(latitude: 12.2958, longitude: 76.6394)
            #endif
            
            if !isMonitoringStarted {
                startFourWheelerMonitoring()
            }
        @unknown default:
            break
        }
    }
    
    func handleLocationUpdate(_ locations: [CLLocation]) {
        if let location = locations.last, location.coordinate.isValid {
            print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            userLocation = location.coordinate
            
            if let simulatedId = self.simulatedFourWheelerId,
               let index = self.fourWheelers.firstIndex(where: { $0.id == simulatedId }) {
                self.fourWheelers[index].currentLocation = location.coordinate
                self.fourWheelers[index].lastUpdated = Date()
                checkFourWheelerStatuses()
            }
            
            objectWillChange.send()
        }
    }
    
    func handleLocationError(_ error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    // MARK: - Route Calculation
    private func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async -> (polylineCoordinates: [CodableCoordinate], distance: Double)? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return nil }
            
            let coordinates = route.polyline.polylineCoordinates
            let codableCoordinates = coordinates.map { CodableCoordinate(coordinate: $0) }
            
            print("Route calculated with \(coordinates.count) points and distance \(route.distance)m")
            return (codableCoordinates, route.distance)
        } catch {
            print("Error calculating route: \(error)")
            
            let directCoordinates = [
                CodableCoordinate(coordinate: start),
                CodableCoordinate(coordinate: end)
            ]
            
            let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let directDistance = startLoc.distance(from: endLoc)
            
            print("Using direct route with distance \(directDistance)m")
            return (directCoordinates, directDistance)
        }
    }
    
    // MARK: - Data Initialization
    @MainActor
    private func initializeHardcodedData() async {
        var routes: [Route] = [
            Route(
                id: UUID(),
                name: "Mysore to Chennai",
                waypoints: [
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 12.2958, longitude: 76.6394), order: 0, locationName: "Mysore"),
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707), order: 1, locationName: "Chennai")
                ],
                corridorWidth: 500.0,
                assignedFourWheelerIds: [UUID()],
                color: .blue
            ),
            Route(
                id: UUID(),
                name: "Bangalore to Hyderabad",
                waypoints: [
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946), order: 0, locationName: "Bangalore"),
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 17.3850, longitude: 78.4867), order: 1, locationName: "Hyderabad")
                ],
                corridorWidth: 400.0,
                assignedFourWheelerIds: [UUID()],
                color: .red
            ),
            Route(
                id: UUID(),
                name: "Kochi to Trivandrum",
                waypoints: [
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 9.9312, longitude: 76.2673), order: 0, locationName: "Kochi"),
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 8.5241, longitude: 76.9366), order: 1, locationName: "Trivandrum")
                ],
                corridorWidth: 300.0,
                assignedFourWheelerIds: [UUID()],
                color: .green
            ),
            Route(
                id: UUID(),
                name: "Coimbatore to Madurai",
                waypoints: [
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 11.0168, longitude: 76.9558), order: 0, locationName: "Coimbatore"),
                    Waypoint(coordinate: CLLocationCoordinate2D(latitude: 9.9252, longitude: 78.1198), order: 1, locationName: "Madurai")
                ],
                corridorWidth: 350.0,
                assignedFourWheelerIds: [UUID()],
                color: .purple
            )
        ]
        
        print("Calculating routes...")
        
        for i in 0..<routes.count {
            guard routes[i].waypoints.count >= 2 else { continue }
            let start = routes[i].waypoints[0].locationCoordinate
            let end = routes[i].waypoints[1].locationCoordinate
            
            print("Calculating route from \(start) to \(end)")
            
            if let (polylineCoordinates, distance) = await calculateRoute(from: start, to: end) {
                routes[i].polylineCoordinates = polylineCoordinates
                routes[i].distance = distance
                print("Route \(routes[i].name) calculated with \(polylineCoordinates.count) points")
            } else {
                print("Failed to calculate route, using direct line")
                routes[i].polylineCoordinates = [
                    CodableCoordinate(coordinate: start),
                    CodableCoordinate(coordinate: end)
                ]
                
                let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
                let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
                routes[i].distance = startLoc.distance(from: endLoc)
            }
        }
        
        var fourWheelers: [FourWheeler] = []
        for (index, route) in routes.enumerated() {
            let fourWheelerId = route.assignedFourWheelerIds.first!
            let initialLocation = route.polylineCoordinates?.first?.coordinate ?? route.waypoints[0].locationCoordinate
            
            let fourWheeler = FourWheeler(
                id: fourWheelerId,
                name: "FourWheeler \(index + 1)",
                currentLocationCoordinate: CodableCoordinate(coordinate: initialLocation),
                assignedRouteId: route.id,
                status: .onRoute,
                lastUpdated: Date(),
                deviation: 0.0
            )
            fourWheelers.append(fourWheeler)
            
            notificationStatusByFourWheeler[fourWheelerId] = false
        }
        
        self.routes = routes
        self.fourWheelers = fourWheelers
        
        if let mysoreChennaiRoute = routes.first(where: { $0.name == "Mysore to Chennai" }) {
            self.simulatedFourWheelerId = mysoreChennaiRoute.assignedFourWheelerIds.first
        }
        
        generateRoutePolylines()
        generateGeofenceOverlays()
        
        startFourWheelerMonitoring()
        
        objectWillChange.send()
    }
    
    // MARK: - FourWheeler Monitoring
    func startFourWheelerMonitoring() {
        guard simulationTimer == nil else { return }
        
        print("Starting four-wheeler monitoring...")
        isMonitoringStarted = true
        
        lastUpdateTime = Date()
        startTime = Date()
        
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
           locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                self.updateFourWheelerLocations()
                
                self.objectWillChange.send()
            }
        }
    }
    
    func stopFourWheelerMonitoring() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        isMonitoringStarted = false
        locationManager.stopUpdatingLocation()
    }
    
    func updateFourWheelerLocations() {
        for i in 0..<fourWheelers.count {
            if let routeId = fourWheelers[i].assignedRouteId,
               let route = routes.first(where: { $0.id == routeId }),
               let polyline = route.polylineCoordinates {
                
                let elapsedTime = Date().timeIntervalSince(lastUpdateTime ?? Date())
                let speed = 30.0 // meters per second
                let distanceToMove = speed * elapsedTime
                
                if fourWheelers[i].name == "FourWheeler 3" {
                    // Simulate FourWheeler 3 moving outside geofence after 10 seconds
                    if let startTime = startTime,
                       Date().timeIntervalSince(startTime) >= 10,
                       !hasFourWheeler3Deviated {
                        simulateFourWheeler3Deviation(fourWheelerIndex: i, route: polyline.map { $0.coordinate })
                        hasFourWheeler3Deviated = true
                    } else {
                        moveFourWheelerAlongRoute(fourWheelerIndex: i, route: polyline.map { $0.coordinate }, distanceToMove: distanceToMove)
                    }
                } else {
                    moveFourWheelerAlongRoute(fourWheelerIndex: i, route: polyline.map { $0.coordinate }, distanceToMove: distanceToMove)
                }
            }
        }
        
        lastUpdateTime = Date()
        checkFourWheelerStatuses()
    }
    
    func moveFourWheelerAlongRoute(fourWheelerIndex: Int, route: [CLLocationCoordinate2D], distanceToMove: Double) {
        guard !route.isEmpty, fourWheelerIndex < fourWheelers.count else { return }
        
        let currentLocation = fourWheelers[fourWheelerIndex].currentLocation ?? route[0]
        
        var closestPointIndex = 0
        var minDistance = Double.greatestFiniteMagnitude
        
        for (index, point) in route.enumerated() {
            let location = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
            let routePoint = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let distance = location.distance(from: routePoint)
            
            if distance < minDistance {
                minDistance = distance
                closestPointIndex = index
            }
        }
        
        let nextPointIndex = min(closestPointIndex + 1, route.count - 1)
        if nextPointIndex == closestPointIndex { return }
        
        let currentPoint = route[closestPointIndex]
        let nextPoint = route[nextPointIndex]
        
        let currentLoc = CLLocation(latitude: currentPoint.latitude, longitude: currentPoint.longitude)
        let nextLoc = CLLocation(latitude: nextPoint.latitude, longitude: nextPoint.longitude)
        let segmentDistance = currentLoc.distance(from: nextLoc)
        
        if segmentDistance > 0 {
            let moveRatio = min(distanceToMove / segmentDistance, 1.0)
            
            let newLat = currentPoint.latitude + moveRatio * (nextPoint.latitude - currentPoint.latitude)
            let newLon = currentPoint.longitude + moveRatio * (nextPoint.longitude - currentPoint.longitude)
            
            fourWheelers[fourWheelerIndex].currentLocation = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
            fourWheelers[fourWheelerIndex].lastUpdated = Date()
        }
    }
    
    func simulateFourWheeler3Deviation(fourWheelerIndex: Int, route: [CLLocationCoordinate2D]) {
        guard !route.isEmpty, fourWheelerIndex < fourWheelers.count else { return }
        
        let currentLocation = fourWheelers[fourWheelerIndex].currentLocation ?? route[0]
        
        // Apply a lateral offset to move FourWheeler 3 outside the geofence
        let avgLat = route.reduce(0) { $0 + $1.latitude } / Double(route.count)
        let metersToLonDegrees = 1.0 / CoordinateUtils.metersPerDegreeLongitude(atLatitude: avgLat)
        let offsetMeters = 400.0 // Move 400 meters off the route (beyond 300m corridor width)
        let offsetLon = offsetMeters * metersToLonDegrees
        
        let newLocation = CLLocationCoordinate2D(
            latitude: currentLocation.latitude,
            longitude: currentLocation.longitude + offsetLon
        )
        
        fourWheelers[fourWheelerIndex].currentLocation = newLocation
        fourWheelers[fourWheelerIndex].lastUpdated = Date()
        
        checkFourWheelerStatuses()
    }
    
    // MARK: - FourWheeler Status Monitoring
    func checkFourWheelerStatuses() {
        for i in 0..<fourWheelers.count {
            guard let fourWheelerLocation = fourWheelers[i].currentLocation,
                  let routeId = fourWheelers[i].assignedRouteId,
                  let route = routes.first(where: { $0.id == routeId }),
                  let routePolyline = route.polylineCoordinates?.map({ $0.coordinate }) else {
                continue
            }
            
            let deviation = calculateMinimumDistanceToRoute(point: fourWheelerLocation, route: routePolyline)
            fourWheelers[i].deviation = deviation
            
            let isWithinCorridor = deviation <= (route.corridorWidth / 2)
            
            let newStatus: FourWheeler.FourWheelerStatus = isWithinCorridor ? .onRoute : .offRoute
            let previousStatus = fourWheelers[i].status
            
            fourWheelers[i].status = newStatus
            
            if newStatus == .offRoute && previousStatus != .offRoute {
                sendOffRouteNotification(for: fourWheelers[i])
            } else if newStatus == .onRoute && previousStatus == .offRoute {
                resetNotificationFlag(for: fourWheelers[i].id)
            }
        }
    }
    
    func calculateMinimumDistanceToRoute(point: CLLocationCoordinate2D, route: [CLLocationCoordinate2D]) -> Double {
        guard route.count >= 2 else { return Double.greatestFiniteMagnitude }
        
        var minDistance = Double.greatestFiniteMagnitude
        
        let avgLat = route.reduce(0) { $0 + $1.latitude } / Double(route.count)
        let metersPerLatDegree = CoordinateUtils.metersPerDegreeLatitude()
        let metersPerLonDegree = CoordinateUtils.metersPerDegreeLongitude(atLatitude: avgLat)
        
        for i in 0..<route.count-1 {
            let p1 = route[i]
            let p2 = route[i+1]
            
            let distance = calculateDistanceFromPointToLineSegment(
                point: point,
                lineStart: p1,
                lineEnd: p2,
                metersPerLatDegree: metersPerLatDegree,
                metersPerLonDegree: metersPerLonDegree
            )
            
            minDistance = min(minDistance, distance)
        }
        
        return minDistance
    }
    
    func calculateDistanceFromPointToLineSegment(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D,
        metersPerLatDegree: Double,
        metersPerLonDegree: Double
    ) -> Double {
        let x = point.longitude * metersPerLonDegree
        let y = point.latitude * metersPerLatDegree
        let x1 = lineStart.longitude * metersPerLonDegree
        let y1 = lineStart.latitude * metersPerLatDegree
        let x2 = lineEnd.longitude * metersPerLonDegree
        let y2 = lineEnd.latitude * metersPerLatDegree
        
        let dx = x2 - x1
        let dy = y2 - y1
        let segmentLengthSq = dx * dx + dy * dy
        
        if segmentLengthSq < 1e-8 {
            let deltaX = x - x1
            let deltaY = y - y1
            return sqrt(deltaX * deltaX + deltaY * deltaY)
        }
        
        let t = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / segmentLengthSq))
        
        let projX = x1 + t * dx
        let projY = y1 + t * dy
        
        let deltaX = x - projX
        let deltaY = y - projY
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
    
    // MARK: - Map Overlays
    func generateRoutePolylines() {
        for route in routes {
            if let coordinates = route.polylineCoordinates?.map({ $0.coordinate }),
               coordinates.count >= 2 {
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                activeRoutePolylines[route.id] = polyline
            }
        }
    }
    
    func generateGeofenceOverlays() {
        for route in routes {
            if let polylineCoordinates = route.polylineCoordinates?.map({ $0.coordinate }),
               polylineCoordinates.count >= 2 {
                
                let uiColor: UIColor
                if let data = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: route.colorData) {
                    uiColor = data.withAlphaComponent(0.4)
                } else {
                    uiColor = UIColor.blue.withAlphaComponent(0.4)
                }
                
                let corridor = GeofenceCorridorOverlay(
                    routeId: route.id,
                    polylineCoordinates: polylineCoordinates,
                    corridorWidth: route.corridorWidth,
                    color: uiColor
                )
                
                activeGeofenceOverlays[route.id] = corridor
            }
        }
    }
}

// MARK: - MKPolyline Extension
extension MKPolyline {
    var polylineCoordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

// MARK: - Main Map View
struct FourWheelerMapView: View {
    @ObservedObject private var pathManager = FourWheelerPathManager.shared
    @State private var mapType: MKMapType = .standard
    @State private var showControls = false
    @State private var showFourWheelerList = false
    @State private var showOffRouteBanner = false
    @State private var offRouteFourWheelerName: String?
    
    var body: some View {
        ZStack(alignment: .top) {
            // Map
            MapView(
                mapRegion: $pathManager.mapRegion,
                mapType: $mapType,
                overlays: getOverlays(),
                annotations: getAnnotations()
            )
            .edgesIgnoringSafeArea(.all)
            
            // Status Bar
            HStack {
                Text("Fleetly")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("Monitoring: \(pathManager.isMonitoringStarted ? "Active" : "Inactive")")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text("On Route: \(pathManager.fourWheelers.filter { $0.status == .onRoute }.count)/\(pathManager.fourWheelers.count)")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.leading, 8)
            }
            .padding()
            .background(
                Color.blue
                    .overlay(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Off-Route Banner
            if showOffRouteBanner, let fourWheelerName = offRouteFourWheelerName {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text("\(fourWheelerName) is off route!")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Dismiss") {
                        withAnimation {
                            showOffRouteBanner = false
                        }
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("Dismiss off-route alert")
                }
                .padding()
                .background(
                    Color.blue
                        .overlay(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 60)
                .transition(.move(edge: .top))
            }
            
            // Floating Action Button (FAB) for Controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        withAnimation {
                            showControls.toggle()
                        }
                    }) {
                        Image(systemName: showControls ? "xmark" : "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(showControls ? "Close controls" : "Open controls")
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
            
            // Expanded Controls
            if showControls {
                VStack(spacing: 12) {
                    Spacer()
                    ControlButton(icon: "map", label: "Map Type", action: toggleMapType)
                    ControlButton(icon: "location.fill", label: "User Location", action: pathManager.centerMapOnUserLocation)
                    ControlButton(icon: "arrow.up.left.and.arrow.down.right", label: "Fit Routes", action: pathManager.fitMapToRoutes)
                    ControlButton(icon: "list.bullet", label: "FourWheelers", action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        showFourWheelerList = true
                    })
                    .padding(.bottom, 80)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear {
            if !pathManager.isMonitoringStarted {
                pathManager.startFourWheelerMonitoring()
            }
        }
        .onReceive(pathManager.$fourWheelers) { fourWheelers in
            if let offRouteFourWheeler = fourWheelers.first(where: { $0.status == .offRoute }),
               pathManager.lastOffRouteFourWheelerId == offRouteFourWheeler.id {
                withAnimation {
                    showOffRouteBanner = true
                    offRouteFourWheelerName = offRouteFourWheeler.name
                }
            }
        }
        .sheet(isPresented: $showFourWheelerList) {
            FourWheelerListView(
                fourWheelers: pathManager.fourWheelers,
                onSelectFourWheeler: { fourWheeler in
                    pathManager.centerMapOnFourWheeler(fourWheeler)
                    showFourWheelerList = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(isPresented: $pathManager.showLocationPermissionAlert) {
            Alert(
                title: Text("Location Access Needed"),
                message: Text("Fleetly requires location access to track four-wheelers in real-time. Please enable 'Always' in Settings."),
                primaryButton: .default(Text("Open Settings"), action: openSettings),
                secondaryButton: .default(Text("Retry")) {
                    pathManager.requestLocationPermission()
                }
            )
        }
    }
    
    private func getOverlays() -> [MKOverlay] {
        var overlays: [MKOverlay] = []
        
        overlays.append(contentsOf: Array(pathManager.activeRoutePolylines.values))
        overlays.append(contentsOf: Array(pathManager.activeGeofenceOverlays.values))
        
        return overlays
    }
    
    private func getAnnotations() -> [MKAnnotation] {
        var annotations: [MKAnnotation] = []
        
        for route in pathManager.routes {
            for waypoint in route.waypoints {
                let annotation = WaypointAnnotation(
                    coordinate: waypoint.locationCoordinate,
                    title: waypoint.locationName,
                    subtitle: "Waypoint \(waypoint.order + 1)"
                )
                annotations.append(annotation)
            }
        }
        
        for fourWheeler in pathManager.fourWheelers {
            if let location = fourWheeler.currentLocation {
                let annotation = FourWheelerAnnotation(
                    coordinate: location,
                    title: fourWheeler.name,
                    subtitle: fourWheeler.status.rawValue,
                    status: fourWheeler.status,
                    name: fourWheeler.name
                )
                annotations.append(annotation)
            }
        }
        
        return annotations
    }
    
    private func toggleMapType() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        withAnimation {
            switch mapType {
            case .standard:
                mapType = .satellite
            case .satellite:
                mapType = .hybrid
            default:
                mapType = .standard
            }
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Control Button View
struct ControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.white)
                Text(label)
                    .font(.body)
                    .foregroundColor(.white)
                    .dynamicTypeSize(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 150)
            .background(Color.blue)
            .clipShape(Capsule())
        }
        .accessibilityLabel(label)
        .padding(.trailing, 16)
    }
}

// MARK: - FourWheeler List View
struct FourWheelerListView: View {
    let fourWheelers: [FourWheeler]
    let onSelectFourWheeler: (FourWheeler) -> Void
    
    var body: some View {
        NavigationView {
            List(fourWheelers) { fourWheeler in
                FourWheelerInfoCard(
                    fourWheeler: fourWheeler,
                    onTap: {
                        onSelectFourWheeler(fourWheeler)
                    }
                )
            }
            .navigationTitle("FourWheelers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - FourWheeler Info Card
struct FourWheelerInfoCard: View {
    let fourWheeler: FourWheeler
    let onTap: () -> Void
    @ObservedObject private var pathManager = FourWheelerPathManager.shared
    
    private var routeDetails: String {
        guard let routeId = fourWheeler.assignedRouteId,
              let route = pathManager.routes.first(where: { $0.id == routeId }),
              route.waypoints.count >= 2 else {
            return "Route: Not assigned"
        }
        let start = route.waypoints[0].locationName
        let end = route.waypoints[1].locationName
        return "Route: \(start) to \(end)"
    }
    
    private var currentLocation: String {
        guard let location = fourWheeler.currentLocation else {
            return "Location: Unknown"
        }
        return "Location: (\(location.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.longitude.formatted(.number.precision(.fractionLength(4)))))"
    }
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            onTap()
        }) {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundColor(fourWheeler.status.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(fourWheeler.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .dynamicTypeSize(.large)
                    Text("Status: \(fourWheeler.status.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .dynamicTypeSize(.medium)
                    Text("Deviation: \(fourWheeler.deviation?.formatted() ?? "N/A") m")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .dynamicTypeSize(.medium)
                    Text(routeDetails)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .dynamicTypeSize(.medium)
                    Text(currentLocation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .dynamicTypeSize(.medium)
                }
                Spacer()
                Circle()
                    .fill(fourWheeler.status.color)
                    .frame(width: 12, height: 12)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fourWheeler.name), Status: \(fourWheeler.status.rawValue), Deviation: \(fourWheeler.deviation?.formatted() ?? "N/A") meters, \(routeDetails), \(currentLocation)")
    }
}

// MARK: - Map View
struct MapView: UIViewRepresentable {
    @Binding var mapRegion: MKCoordinateRegion
    @Binding var mapType: MKMapType
    var overlays: [MKOverlay]
    var annotations: [MKAnnotation]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.region = mapRegion
        mapView.mapType = mapType
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        if mapView.region.center.latitude != mapRegion.center.latitude ||
           mapView.region.center.longitude != mapRegion.center.longitude ||
           mapView.region.span.latitudeDelta != mapRegion.span.latitudeDelta ||
           mapView.region.span.longitudeDelta != mapRegion.span.longitudeDelta {
            mapView.setRegion(mapRegion, animated: true)
        }
        
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        
        let currentOverlays = mapView.overlays
        mapView.removeOverlays(currentOverlays)
        mapView.addOverlays(overlays)
        
        let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(Array(currentAnnotations))
        mapView.addAnnotations(annotations)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 3
                return renderer
            } else if let geofence = overlay as? GeofenceCorridorOverlay {
                let renderer = MKPolygonRenderer(polygon: geofence.polygon)
                renderer.fillColor = geofence.color
                renderer.strokeColor = geofence.color.withAlphaComponent(0.8)
                renderer.lineWidth = 2
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            if let fourWheelerAnnotation = annotation as? FourWheelerAnnotation {
                let identifier = "FourWheeler_\(fourWheelerAnnotation.name ?? "Unknown")"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: fourWheelerAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                    
                    // Assign different icons based on the four-wheeler name
                    switch fourWheelerAnnotation.name {
                    case "FourWheeler 1":
                        annotationView?.glyphImage = UIImage(systemName: "car.fill")
                    case "FourWheeler 2":
                        annotationView?.glyphImage = UIImage(systemName: "truck.fill")
                    case "FourWheeler 3":
                        annotationView?.glyphImage = UIImage(systemName: "suv.side.fill")
                    case "FourWheeler 4":
                        annotationView?.glyphImage = UIImage(systemName: "van.fill")
                    default:
                        annotationView?.glyphImage = UIImage(systemName: "car.fill")
                    }
                } else {
                    annotationView?.annotation = fourWheelerAnnotation
                }
                
                switch fourWheelerAnnotation.status {
                case .onRoute:
                    annotationView?.markerTintColor = .green
                case .offRoute:
                    annotationView?.markerTintColor = .red
                    annotationView?.animatesWhenAdded = true
                case .unknown:
                    annotationView?.markerTintColor = .gray
                }
                
                return annotationView
            } else if let waypointAnnotation = annotation as? WaypointAnnotation {
                let identifier = "Waypoint"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: waypointAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                    annotationView?.glyphImage = UIImage(systemName: "mappin")
                } else {
                    annotationView?.annotation = waypointAnnotation
                }
                
                annotationView?.markerTintColor = .purple
                
                return annotationView
            }
            
            return nil
        }
    }
}

// MARK: - Custom Annotations
class FourWheelerAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    var status: FourWheeler.FourWheelerStatus
    var name: String?
    
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, status: FourWheeler.FourWheelerStatus, name: String?) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.name = name
        super.init()
    }
}

class WaypointAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}
