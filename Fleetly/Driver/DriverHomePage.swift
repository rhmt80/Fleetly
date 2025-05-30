import SwiftUI
import MapKit
import CoreLocation
struct MainView: View {
    @ObservedObject var authVM: AuthViewModel
    @State private var showProfile = false
    
    var body: some View {
        TabView {
            DriverHomePage(authVM: authVM, showProfile: $showProfile)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            PastRideContentView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
            TicketsView()
                .tabItem {
                    Label("Tickets", systemImage: "ticket.fill")
                }
        }
        /*.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showProfile = true
                }) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.blue)
                }
            }
        }*/
        .sheet(isPresented: $showProfile) {
            DriverProfileView(authVM: authVM)
        }
        .environmentObject(authVM) // Inject AuthViewModel into the environment for all tabs
    }
}

struct DriverHomePage: View {
    @ObservedObject var authVM: AuthViewModel
    @Binding var showProfile: Bool
    @State private var currentTime = Date()
    @State private var elapsedTime: TimeInterval = 0
    @State private var isStopwatchRunning = false
    @State private var startTime: Date? = nil
    @State private var isNavigating = false
    @State private var userTrackingMode: MapUserTrackingMode = .follow
    @State private var isClockedIn = false
    @State private var currentWorkOrderIndex: Int = 0
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwiping: Bool = false
    @State private var isDragCompleted: Bool = false
    @StateObject private var assignedTripsVM = AssignedTripsViewModel()
    @State private var didStartListener = false
    @State private var profileImage: Image?

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let hours = (0...12).map { $0 == 0 ? "0hr" : "\($0)hr\($0 == 1 ? "" : "s")" }
    
    let dropoffLocation = "Kolkata"
    let vehicleNumber: String = "KA6A1204"
    private let profileImageKey = "profileImage"

    
    static let darkGray = Color(red: 68/255, green: 6/255, blue: 52/255)
    static let lightGray = Color(red: 240/255, green: 242/255, blue: 245/255)
    static let highlightYellow = Color(red: 235/255, green: 64/255, blue: 52/255)
    static let todayGreen = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let customBlue = Color(.systemBlue)
    static let gradientStart = Color(red: 74/255, green: 145/255, blue: 226/255)
    static let gradientEnd = Color(red: 80/255, green: 227/255, blue: 195/255)
    static let initialCapsuleColor = Color(.systemGray5)
    
    private var maxX: CGFloat {
        return 343.0 - 53.0 // Capsule width - Circle diameter
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    private func initializeData() {
        guard let driverId = authVM.user?.id else { return }
        
        FirebaseManager.shared.fetchTodayWorkedTime(driverId: driverId) { result in
            switch result {
            case .success(let totalSeconds):
                elapsedTime = TimeInterval(totalSeconds)
                
                FirebaseManager.shared.fetchAttendanceRecord(driverId: driverId, date: currentDateString()) { recordResult in
                    switch recordResult {
                    case .success(let record):
                        if let record = record {
                            startTime = record.clockInTime.dateValue()
                            if let lastEvent = record.clockEvents.last {
                                isClockedIn = lastEvent.type == "clockIn"
                                isStopwatchRunning = isClockedIn
                            }
                        }
                    case .failure(let error):
                        print("Error fetching attendance record: \(error)")
                    }
                }
            case .failure(let error):
                print("Error fetching worked time: \(error)")
            }
        }
        
        // Load profile image from UserDefaults
        if let data = UserDefaults.standard.data(forKey: profileImageKey),
           let uiImage = UIImage(data: data) {
            profileImage = Image(uiImage: uiImage)
        } else {
            profileImage = nil
        }
    }
    
    
    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm a"
        return formatter
    }
    
    private func formatElapsedTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d HRS", hours, minutes, seconds)
    }
    
    private func isNewDay(_ start: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: start)
        let startOfNow = calendar.startOfDay(for: now)
        return startOfNow > startOfToday
    }
    
/*  private var headerSection: some View {
        HStack {
            VStack{
                Text("Here's your schedule for today!")
                    .font(.system(size: 15, design: .default))
                    .foregroundStyle(Color.secondary)
                    .padding(.trailing, 100)
            }
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.primary)
            }
            .offset(y: -40)
        }
    }*/
    
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Here's your schedule for today!")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            Button(action: {
                print("Profile image tapped") // Debug
                showProfile = true
            }) {
                Group {
                    if let profileImage = profileImage {
                        profileImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(Color.primary)
                    }
                }
                .contentShape(Circle()) // Ensure entire circle is tappable
            }
        }
        .padding(.horizontal)
    }
    




    
    private var workingHoursSection: some View {
        VStack {
            Text("Working Hours")
                .font(.system(size: 24, weight: .semibold, design: .default))
                .foregroundStyle(Color.primary)
                .frame(width: 200, height: 50, alignment: .leading)
                .padding(.trailing, 150)
        }
    }
    
    private var workingHoursContent: some View {
        ZStack {
            Rectangle()
                .fill(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                .frame(width: 363, height: 290)
                .cornerRadius(10)
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            
            VStack(spacing: 10) {
                Text(currentTime, formatter: dateFormatter)
                    .font(.system(size: 20, weight: .regular, design: .default))
                    .foregroundStyle(Color.primary)
                    .padding(.trailing, 210)
                    .padding(.top, 40)
                
                if !isClockedIn {
                    Text("Clocked Hours")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundStyle(Color.secondary)
                        .padding(.trailing, 200)
                } else {
                    Text("")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .frame(height: 20)
                        .padding(.trailing, 200)
                }
                
                Text(formatElapsedTime(elapsedTime))
                    .font(.system(size: 36, weight: .semibold, design: .default))
                    .foregroundStyle(Color.primary)
                    .padding(.leading, 0)
                    .padding(.trailing, 90)
                
                if !isClockedIn, let start = startTime {
                    Text("Since first in at \(start, formatter: timeFormatter)")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundStyle(Color.secondary)
                        .padding(.trailing, 130)
                } else {
                    Text("")
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundStyle(Color.secondary)
                        .padding(.trailing, 200)
                }
                //hfguhik
                ScrollView(.horizontal, showsIndicators: false) {
                                    VStack(spacing: 10) {
                                        ZStack(alignment: .leading) {
                                            // Background track with rounded corners
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.blue.opacity(0.1))
                                                .frame(width: 684, height: 12)
                                                .padding(.horizontal, 10)
                                            
                                            // Progress bar calculation - more precise calculation
                                            let progressWidth: CGFloat = {
                                                let maxTime: TimeInterval = 12 * 3600 // 12 hours in seconds
                                                let progress = min(elapsedTime / maxTime, 1.0)
                                                return 684 * progress
                                            }()
                                            
                                            // Progress bar with rounded corners and gradient
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue]),
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: max(progressWidth, 0), height: 12)
                                                .padding(.leading, 10)
                                                // Add subtle shadow for depth
                                                .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 1)
                                            
                                            // Hour markers - every hour
                                            HStack(spacing: 0) {
                                                ForEach(0..<13, id: \.self) { index in
                                                    Rectangle()
                                                        .fill(index % 3 == 0 ? Color.blue.opacity(0.6) : Color.blue.opacity(0.4))
                                                        .frame(width: index % 3 == 0 ? 2 : 1.5, height: index % 3 == 0 ? 12 : 8)
                                                        .padding(.leading, index == 0 ? 10 : 0)
                                                    
                                                    if index < 12 {
                                                        Spacer()
                                                            .frame(width: 684/12 - 2)
                                                    }
                                                }
                                            }
                                            
                                            // Minute markers (smaller ticks)
                                            HStack(spacing: 0) {
                                                ForEach(0..<49, id: \.self) { index in
                                                    if index % 4 != 0 { // Skip positions where hour markers are
                                                        Rectangle()
                                                            .fill(Color.blue.opacity(0.25))
                                                            .frame(width: 1, height: 5)
                                                            .padding(.leading, index == 0 ? 10 : 0)
                                                    } else {
                                                        Rectangle()
                                                            .fill(Color.clear)
                                                            .frame(width: 1, height: 5)
                                                    }
                                                    
                                                    if index < 48 {
                                                        Spacer()
                                                            .frame(width: 684/48 - 1)
                                                    }
                                                }
                                            }
                                            
                                            // Current progress indicator (small circle)
                                            if progressWidth > 0 {
                                                Circle()
                                                    .fill(Color.white)
                                                    .frame(width: 8, height: 8)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.blue, lineWidth: 2)
                                                    )
                                                    .padding(.leading, progressWidth + 6) // Position it at the end of progress bar
                                            }
                                        }
                                        
                                        // Hour labels with consistent styling and better visibility
                                        HStack(spacing: 0) {
                                            ForEach(0..<13, id: \.self) { hour in
                                                Text(hour == 0 ? "0hr" : "\(hour)hr\(hour == 1 ? "" : "s")")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(Color.primary)
                                                    .frame(width: 684/12)
                                                    .multilineTextAlignment(.center)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                    }
                                }
                                .frame(width: 343) // Constrain to parent width
                //gjkhkhk
                VStack {
                    Button(action: {
                        guard let driverId = authVM.user?.id else { return }
                        
                        isClockedIn.toggle()
                        let eventType = isClockedIn ? "clockIn" : "clockOut"
                        
                        FirebaseManager.shared.recordClockEvent(driverId: driverId, type: eventType) { result in
                            switch result {
                            case .success:
                                if isClockedIn {
                                    print("Driver Clocked in")
                                    isStopwatchRunning = true
                                } else {
                                    print("Driver Clocked out")
                                    isStopwatchRunning = false
                                    FirebaseManager.shared.fetchTodayWorkedTime(driverId: driverId) { timeResult in
                                        switch timeResult {
                                        case .success(let totalSeconds):
                                            elapsedTime = TimeInterval(totalSeconds)
                                        case .failure(let error):
                                            print("Error fetching updated worked time: \(error)")
                                        }
                                    }
                                }
                            case .failure(let error):
                                print("Error recording clock event: \(error)")
                                isClockedIn.toggle()
                            }
                        }
                    }) {
                        Label(isClockedIn ? "Clock Out" : "Clock In", systemImage: "person.crop.circle.badge.clock")
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundStyle(Color.white)
                            .frame(width: 312, height: 35)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isClockedIn ? Color(red: 243/255, green: 120/255, blue: 89/255) : Color(red: 3/255, green: 218/255, blue: 164/255))
                    .padding(.bottom, 20)
                }
                Spacer()
            }
        }
        .offset(y: -25)
    }
    
    private var tripsHeader: some View {
        HStack {
            Text("Assigned Trips")
                .font(.title2.bold())
                .foregroundStyle(Color.primary)
            
            if !assignedTripsVM.assignedTrips.isEmpty {
                Text("\(assignedTripsVM.assignedTrips.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    // State to manage each trip's map data
    struct TripMapData {
        var region: MKCoordinateRegion
        var pickup: Location?
        var drop: Location?
        var route: MKRoute?
        
        init() {
            self.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
            self.pickup = nil
            self.drop = nil
            self.route = nil
        }
    }
    
    @State private var tripMapData: [String: TripMapData] = [:] // Map trip ID to its map data
    
    private func fetchRoute(for trip: Trip) {
        // Initialize map data for this trip if not already present
        if tripMapData[trip.id] == nil {
            tripMapData[trip.id] = TripMapData()
        }
        
        let geocoder = CLGeocoder()
        
        // Geocode startLocation
        geocoder.geocodeAddressString(trip.startLocation) { placemarks, error in
            guard let startPlacemark = placemarks?.first,
                  let startLocation = startPlacemark.location else {
                print("Failed to geocode start location: \(trip.startLocation), error: \(String(describing: error))")
                return
            }
            
            // Geocode endLocation
            geocoder.geocodeAddressString(trip.endLocation) { placemarks, error in
                guard let endPlacemark = placemarks?.first,
                      let endLocation = endPlacemark.location else {
                    print("Failed to geocode end location: \(trip.endLocation), error: \(String(describing: error))")
                    return
                }
                
                let pickup = Location(name: trip.startLocation, coordinate: startLocation.coordinate)
                let drop = Location(name: trip.endLocation, coordinate: endLocation.coordinate)
                
                // Calculate the route
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: startLocation.coordinate))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: endLocation.coordinate))
                request.transportType = .automobile
                
                let directions = MKDirections(request: request)
                directions.calculate { response, error in
                    guard let route = response?.routes.first else {
                        print("Failed to calculate route: \(String(describing: error))")
                        return
                    }
                    
                    // Calculate the region to encompass the entire route
                    let coordinates = route.polyline.coordinates
                    let region = MKCoordinateRegion(coordinates: coordinates, latitudinalMetersPadding: 1000, longitudinalMetersPadding: 1000)
                    
                    // Update the trip's map data
                    DispatchQueue.main.async {
                        tripMapData[trip.id]?.region = region
                        tripMapData[trip.id]?.pickup = pickup
                        tripMapData[trip.id]?.drop = drop
                        tripMapData[trip.id]?.route = route
                    }
                }
            }
        }
    }
    
    // MARK: - Trip Card Components
    private struct TripMapSection: View {
        let mapData: TripMapData
        
        var body: some View {
            MapViewWithRoute(
                region: .constant(mapData.region),
                pickup: mapData.pickup ?? Location(name: "Default Start", coordinate: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)),
                drop: mapData.drop ?? Location(name: "Default End", coordinate: CLLocationCoordinate2D(latitude: 22.5726, longitude: 88.3639)),
                route: mapData.route,
                mapStyle: .constant(.standard),
                isTripStarted: false,
                userLocationCoordinate: nil
            )
            .frame(width: 300, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private struct TripLocationSection: View {
        let trip: Trip
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                LocationRow(icon: "mappin.circle.fill", color: .blue, label: "From", value: trip.startLocation)
                LocationRow(icon: "mappin.circle.fill", color: .green, label: "To", value: trip.endLocation)
            }
        }
    }

    private struct LocationRow: View {
        let icon: String
        let color: Color
        let label: String
        let value: String
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    Text(value)
                        .font(.headline)
                }
            }
        }
    }

    private struct TripDetailsSection: View {
        let trip: Trip
        
        var body: some View {
            HStack(spacing: 24) {
                DetailColumn(label: "Time", value: trip.time)
                DetailColumn(label: "Vehicle Type", value: trip.vehicleType)
                DetailColumn(
                    label: trip.vehicleType == "Passenger Vehicle" ? "Passengers" : "Load",
                    value: trip.vehicleType == "Passenger Vehicle" ?
                        "\(trip.passengers ?? 0)" :
                        "\(Int(trip.loadWeight ?? 0)) kg"
                )
            }
        }
    }

    private struct DetailColumn: View {
        let label: String
        let value: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                Text(value)
                    .font(.headline)
            }
        }
    }

  /* private struct TripActionButton: View {
        let trip: Trip
        @Binding var isNavigating: Bool
        @Binding var swipeOffset: CGFloat
        @Binding var isDragCompleted: Bool
        @Binding var isSwiping: Bool
        let maxX: CGFloat
        let authVM: AuthViewModel
        let gradientStart: Color
        let gradientEnd: Color
        @Environment(\.colorScheme) var colorScheme
        
        var body: some View {
            
            ZStack(alignment: .leading) {
                NavigationLink(
                    destination: PreInspectionView(
                        authVM: authVM,
                        dropoffLocation: trip.endLocation,
                        vehicleNumber: trip.vehicleId,
                        tripID: trip.id,
                        vehicleID: trip.vehicleId
                    ),
                    isActive: $isNavigating,
                    label: {
                        LinearGradient(
                            colors: swipeOffset == 0 ? [Color(.systemGray5), Color(.systemGray5)] : [
                                gradientStart,
                                swipeOffset >= maxX - 10 || isDragCompleted ? gradientEnd : gradientStart
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 55)
                        .clipShape(Capsule())
                    }
                )
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemBlue))
                            .frame(width: 53, height: 53)
                        Image(systemName: "car.side.fill")
                            .scaleEffect(x: -1, y: 1)
                            .foregroundStyle(Color(.systemBackground))
                    }
                    .padding(.trailing, 16)
                    .offset(x: swipeOffset)
                    .gesture(
                        isDragCompleted ? nil : DragGesture()
                            .onChanged { value in
                                isSwiping = true
                                let newOffset = max(value.translation.width, 0)
                                //let newOffset = min(max(0, value.translation.width), maxX)claude
                                swipeOffset = min(newOffset, maxX)
                                swipeOffset = newOffset
                                //swipeOffset = min(max(0, value.translation.width), maxX)


                            }
                            .onEnded { _ in
                                isSwiping = false
                                if swipeOffset >= maxX - 10 {
                                    swipeOffset = maxX
                                    isDragCompleted = true
                                    isNavigating = true
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        swipeOffset = 0
                                    }
                                }
                            }
                    )
                    
                    Spacer()
                    
                    Text("Slide to get Ready")
                        .font(.headline)
                        .foregroundColor(swipeOffset > 0 || isDragCompleted ? .white : Color(.systemBlue))
                        .padding(.trailing, 16)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
           // .frame(width: 343) // Explicitly set width to match the maxX calculation

            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
        }
    }*/
    
  /* CLAUde private struct TripActionButton: View {
        let trip: Trip
        @Binding var isNavigating: Bool
        @Binding var swipeOffset: CGFloat
        @Binding var isDragCompleted: Bool
        @Binding var isSwiping: Bool
        let maxX: CGFloat
        let authVM: AuthViewModel
        let gradientStart: Color
        let gradientEnd: Color
        @State private var dragStartLocation: CGFloat = 0
        @Environment(\.colorScheme) var colorScheme
        
        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    NavigationLink(
                        destination: PreInspectionView(
                            authVM: authVM,
                            dropoffLocation: trip.endLocation,
                            vehicleNumber: trip.vehicleId,
                            tripID: trip.id,
                            vehicleID: trip.vehicleId
                        ),
                        isActive: $isNavigating,
                        label: {
                            LinearGradient(
                                colors: swipeOffset == 0 ? [Color(.systemGray5), Color(.systemGray5)] : [
                                    gradientStart,
                                    swipeOffset >= maxX - 10 || isDragCompleted ? gradientEnd : gradientStart
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(height: 55)
                            .clipShape(Capsule())
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                    
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBlue))
                                .frame(width: 53, height: 53)
                            Image(systemName: "car.side.fill")
                                .scaleEffect(x: -1, y: 1)
                                .foregroundStyle(Color(.systemBackground))
                        }
                        .offset(x: swipeOffset)
                        .gesture(
                            isDragCompleted ? nil : DragGesture()
                                .onChanged { value in
                                    isSwiping = true
                                    // Constrain the offset to the available space within the capsule
                                    swipeOffset = min(max(0, value.translation.width), maxX)
                                }
                                .onEnded { _ in
                                    isSwiping = false
                                    if swipeOffset >= maxX - 10 {
                                        swipeOffset = maxX
                                        isDragCompleted = true
                                        isNavigating = true
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            swipeOffset = 0
                                        }
                                    }
                                }
                        )
                        
                        Spacer()
                        
                        Text("Slide to get Ready")
                            .font(.headline)
                            .foregroundColor(swipeOffset > 0 || isDragCompleted ? .white : Color(.systemBlue))
                            .padding(.trailing, 16)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: geometry.size.width)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6))
                        .overlay(
                            Capsule()
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                )
            }
            .frame(height: 55)
            .padding(.horizontal, 8)
        }
    }
*/
 //MARK:- Working
  /*WORKING YEY!!
    struct TripActionButton: View {
        let trip: Trip
        @Binding var isNavigating: Bool
        @Binding var swipeOffset: CGFloat
        @Binding var isDragCompleted: Bool
        @Binding var isSwiping: Bool
        let maxX: CGFloat
        let authVM: AuthViewModel
        let gradientStart: Color
        let gradientEnd: Color
        @Environment(\.colorScheme) var colorScheme
        
        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Navigation link with gradient background
                    NavigationLink(
                        destination: PreInspectionView(
                            authVM: authVM,
                            dropoffLocation: trip.endLocation,
                            vehicleNumber: trip.vehicleId,
                            tripID: trip.id,
                            vehicleID: trip.vehicleId
                        ),
                        isActive: $isNavigating,
                        label: {
                            LinearGradient(
                                colors: swipeOffset == 0 ? [Color(.systemGray5), Color(.systemGray5)] : [
                                    gradientStart,
                                    swipeOffset >= maxX - 10 || isDragCompleted ? gradientEnd : gradientStart
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width, height: 55)
                            .clipShape(Capsule())
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                    
                    // Content with sliding circle
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBlue))
                                .frame(width: 53, height: 53)
                            Image(systemName: "car.side.fill")
                                .scaleEffect(x: -1, y: 1)
                                .foregroundStyle(Color(.systemBackground))
                        }
                        .offset(x: swipeOffset)
                        .gesture(
                            isDragCompleted ? nil : DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    isSwiping = true
                                    // Calculate maximum drag distance based on actual capsule width
                                    let calculatedMaxX = geometry.size.width - 53 // Width minus circle width
                                    swipeOffset = min(max(0, value.translation.width), calculatedMaxX)
                                }
                                .onEnded { _ in
                                    isSwiping = false
                                    let calculatedMaxX = geometry.size.width - 53
                                    if swipeOffset >= calculatedMaxX - 10 {
                                        swipeOffset = calculatedMaxX
                                        isDragCompleted = true
                                        isNavigating = true
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            swipeOffset = 0
                                        }
                                    }
                                }
                        )
                        
                        Spacer()
                        
                        Text("Slide to get Ready")
                            .font(.headline)
                            .foregroundColor(swipeOffset > 0 || isDragCompleted ? .white : Color(.systemBlue))
                            .padding(.trailing, 16)
                    }
                    .padding(.leading, 0) // Removed horizontal padding from left
                    .padding(.trailing, 8) // Keep padding on right side only
                }
            }
            .frame(height: 55)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
        }
    }*/
    
  /* DISAPPEARING WORKING
   struct TripActionButton: View {
        let trip: Trip
        @Binding var isNavigating: Bool
        @Binding var swipeOffset: CGFloat
        @Binding var isDragCompleted: Bool
        @Binding var isSwiping: Bool
        let maxX: CGFloat
        let authVM: AuthViewModel
        let gradientStart: Color
        let gradientEnd: Color
        @Environment(\.colorScheme) var colorScheme
        @State private var sliderOpacity: Double = 1.0
        
        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Navigation link with gradient background
                    NavigationLink(
                        destination: PreInspectionView(
                            authVM: authVM,
                            dropoffLocation: trip.endLocation,
                            vehicleNumber: trip.vehicleId,
                            tripID: trip.id,
                            vehicleID: trip.vehicleId
                        ),
                        isActive: $isNavigating,
                        label: {
                            LinearGradient(
                                colors: swipeOffset == 0 ? [Color(.systemGray5), Color(.systemGray5)] : [
                                    gradientStart,
                                    swipeOffset >= maxX - 10 || isDragCompleted ? gradientEnd : gradientStart
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width, height: 55)
                            .clipShape(Capsule())
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                    
                    // Content with sliding circle
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBlue))
                                .frame(width: 53, height: 53)
                            Image(systemName: "car.side.fill")
                                .scaleEffect(x: -1, y: 1)
                                .foregroundStyle(Color(.systemBackground))
                        }
                        .opacity(sliderOpacity)
                        .offset(x: swipeOffset)
                        .gesture(
                            isDragCompleted ? nil : DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    isSwiping = true
                                    // Calculate maximum drag distance based on actual capsule width
                                    let calculatedMaxX = geometry.size.width - 53 // Width minus circle width
                                    swipeOffset = min(max(0, value.translation.width), calculatedMaxX)
                                }
                                .onEnded { _ in
                                    isSwiping = false
                                    let calculatedMaxX = geometry.size.width - 53
                                    if swipeOffset >= calculatedMaxX - 10 {
                                        swipeOffset = calculatedMaxX
                                        isDragCompleted = true
                                        
                                        // Animate the slider to fade out
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            sliderOpacity = 0
                                        }
                                        
                                        // Small delay before navigating
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            isNavigating = true
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            swipeOffset = 0
                                        }
                                    }
                                }
                        )
                        
                        Spacer()
                        
                        Text("Slide to get Ready")
                            .font(.headline)
                            .foregroundColor(swipeOffset > 0 || isDragCompleted ? .white : Color(.systemBlue))
                            .padding(.trailing, 16)
                    }
                    .padding(.leading, 0) // Removed horizontal padding from left
                    .padding(.trailing, 8) // Keep padding on right side only
                }
            }
            .frame(height: 55)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
            .onAppear {
                // Reset opacity when view appears
                sliderOpacity = 1.0
            }
        }
    }*/
    
    struct TripActionButton: View {
        let trip: Trip
        @Binding var isNavigating: Bool
        @Binding var swipeOffset: CGFloat
        @Binding var isDragCompleted: Bool
        @Binding var isSwiping: Bool
        let maxX: CGFloat
        let authVM: AuthViewModel
        let gradientStart: Color
        let gradientEnd: Color
        @Environment(\.colorScheme) var colorScheme
        @State private var sliderOpacity: Double = 1.0
        
        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Navigation link with gradient background
                    NavigationLink(
                        destination: PreInspectionView(
                            authVM: authVM,
                            dropoffLocation: trip.endLocation,
                            vehicleNumber: trip.vehicleId,
                            tripID: trip.id,
                            vehicleID: trip.vehicleId
                        ),
                        isActive: $isNavigating,
                        label: {
                            LinearGradient(
                                colors: swipeOffset == 0 ? [Color(.systemGray5), Color(.systemGray5)] : [
                                    gradientStart,
                                    swipeOffset >= maxX - 10 || isDragCompleted ? gradientEnd : gradientStart
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width, height: 55)
                            .clipShape(Capsule())
                        }
                    )
                    .buttonStyle(PlainButtonStyle())
                    
                    // Content with sliding circle
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBlue))
                                .frame(width: 53, height: 53)
                            Image(systemName: "car.side.fill")
                                .scaleEffect(x: -1, y: 1)
                                .foregroundStyle(Color(.systemBackground))
                        }
                        .opacity(sliderOpacity)
                        .offset(x: swipeOffset)
                        .gesture(
                            isDragCompleted ? nil : DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    isSwiping = true
                                    // Calculate maximum drag distance based on actual capsule width
                                    let calculatedMaxX = geometry.size.width - 53 // Width minus circle width
                                    swipeOffset = min(max(0, value.translation.width), calculatedMaxX)
                                }
                                .onEnded { _ in
                                    isSwiping = false
                                    let calculatedMaxX = geometry.size.width - 53
                                    if swipeOffset >= calculatedMaxX - 10 {
                                        swipeOffset = calculatedMaxX
                                        isDragCompleted = true
                                        
                                        // Animate the slider to fade out
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            sliderOpacity = 0
                                        }
                                        
                                        // Small delay before navigating
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            isNavigating = true
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            swipeOffset = 0
                                        }
                                    }
                                }
                        )
                        
                        Spacer()
                        
                        Text("Slide to get Ready")
                            .font(.headline)
                            .foregroundColor(swipeOffset > 0 || isDragCompleted ? .white : Color(.systemBlue))
                            .padding(.trailing, 16)
                    }
                    .padding(.leading, 0)
                    .padding(.trailing, 8)
                }
            }
            .frame(height: 55)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 8)
            .onAppear {
                // Reset slider state when view appears or reappears
                resetSliderState()
            }
            .onChange(of: isNavigating) { newValue in
                // When navigating back (isNavigating changes from true to false)
                if !newValue {
                    resetSliderState()
                }
            }
        }
        
        // Helper function to reset slider state
        private func resetSliderState() {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                swipeOffset = 0
                isDragCompleted = false
                sliderOpacity = 1.0
            }
        }
    }
    
    // MARK: - Main Trip Card View
    private func tripCardView(for trip: Trip) -> some View {
        let mapData = tripMapData[trip.id] ?? TripMapData()
        
        return VStack(spacing: 0) {
            TripMapSection(mapData: mapData)
            
            VStack(alignment: .leading, spacing: 16) {
                TripLocationSection(trip: trip)
                
                Divider()
                
                TripDetailsSection(trip: trip)
                
                TripActionButton(
                    trip: trip,
                    isNavigating: $isNavigating,
                    swipeOffset: $swipeOffset,
                    isDragCompleted: $isDragCompleted,
                    isSwiping: $isSwiping,
                    maxX: maxX,
                    authVM: authVM,
                    gradientStart: Self.gradientStart,
                    gradientEnd: Self.gradientEnd
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
        }
        .frame(width: 300)
        .onAppear {
            fetchRoute(for: trip)
        }
    }
    
    private var tripsListView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(assignedTripsVM.assignedTrips) { trip in
                    tripCardView(for: trip)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var emptyOrLoadingStateView: some View {
        Group {
            if assignedTripsVM.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            } else if !assignedTripsVM.assignedTrips.isEmpty {
                tripsListView
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "car.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.secondary)
                    Text("No trips assigned")
                        .font(.headline)
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
        }
    }
    
    private var assignedTripSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            tripsHeader
            emptyOrLoadingStateView
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.systemGray6))
                    .ignoresSafeArea(.all, edges: .top)
                    .ignoresSafeArea(.keyboard)
                
                ScrollView {
                    VStack {
                        headerSection
                        workingHoursSection
                        workingHoursContent
                        assignedTripSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Hello, \(authVM.user?.name ?? "Param Patel")")
                .onReceive(timer) { _ in
                    currentTime = Date()
                    if isStopwatchRunning {
                        elapsedTime += 1
                    }
                }
                .onAppear {
                    initializeData()
                    guard !didStartListener,
                          let driverId = authVM.user?.id
                    else { return }
                    assignedTripsVM.startListening(driverId: driverId)
                    didStartListener = true
                }
                .onChange(of: showProfile) { newValue in
                    // Reload profile image when profile sheet is dismissed
                    if !newValue {
                        if let data = UserDefaults.standard.data(forKey: profileImageKey),
                           let uiImage = UIImage(data: data) {
                            profileImage = Image(uiImage: uiImage)
                        } else {
                            profileImage = nil
                        }
                    }
                }
            }
        }
    }
}
// Extension to calculate a region encompassing a set of coordinates
extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D], latitudinalMetersPadding: CLLocationDistance, longitudinalMetersPadding: CLLocationDistance) {
        guard !coordinates.isEmpty else {
            self.init(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
            return
        }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) + (latitudinalMetersPadding / 111320.0), // Rough conversion: 1 degree latitude ~ 111,320 meters
            longitudeDelta: (maxLon - minLon) + (longitudinalMetersPadding / (111320.0 * cos(center.latitude * .pi / 180.0)))
        )
        
        self.init(center: center, span: span)
    }
}

// Corrected extension to get coordinates from MKPolyline
extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        coords.withUnsafeMutableBufferPointer { ptr in
            getCoordinates(ptr.baseAddress!, range: NSRange(location: 0, length: pointCount))
        }
        return coords
    }
}

// Define Location struct if not already defined elsewhere
/*struct Location {
    let coordinate: CLLocationCoordinate2D
    let name: String
}*/


//hello
