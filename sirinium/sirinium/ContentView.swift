import SwiftUI
import Combine
import UserNotifications

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .light: return "Светлая"
        case .dark: return "Темная"
        case .system: return "Системная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

class NotificationSettings: ObservableObject {
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false
    @AppStorage("notificationTime") var notificationTime: Double = 10 // minutes before class
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @StateObject private var notificationSettings = NotificationSettings()

    @State private var selectedDay: String = {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        switch weekday {
        case 2: return "ПН"
        case 3: return "ВТ"
        case 4: return "СР"
        case 5: return "ЧТ"
        case 6: return "ПТ"
        case 7: return "СБ"
        case 1: return "ВС"
        default: return "ПН"
        }
    }()

    @AppStorage("selectedGroup") private var selectedGroupStored: String = ""
    @AppStorage("selectedTeacher") private var selectedTeacherStored: String = ""
    @AppStorage("autoRefreshInterval") private var autoRefreshIntervalStored: Double = 60
    @AppStorage("appTheme") private var appThemeStored: String = AppTheme.system.rawValue

    @State private var selectedGroup: String = ""
    @State private var selectedTeacher: String = ""
    @State private var autoRefreshInterval: Double = 60
    @State private var appTheme: AppTheme = .system

    @State private var refreshTimerCancellable: AnyCancellable?
    @State private var dayChangeTimer: Timer?
    
    @State private var scheduleNotificationCancellable: AnyCancellable?

    private let groups = [
        "К0709-23/1", "К0709-23/2", "К0709-23/3", "К0709-24/1", "К0709-24/2",
        "К0109-23", "К0609-23", "К0409-23", "К0711-23", "К0611-23",
        "К0411-23", "К0709-22", "К0609-22", "К0409-22", "К0109-22",
        "К1609-22/1", "К1609-22/2", "К0711-22", "К0411-22", "К0611-22",
        "К0111-22", "К0609-24", "К0109-24", "К0409-24/1", "К0409-24/2",
        "К1609-24/1", "К1609-24/2"
    ]

    private let englishTeachers = [
        "Биккинина Элина Рамилевна",
        "Ростова Анжелика Юрьевна",
        "Жижонкова Маргарита Сергеевна",
        "Синянская Ирина Викторовна"
    ]

    let daysOfWeek = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
    
    @State private var showDayChangeAlert = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        TabView {
            ScheduleView(
                viewModel: viewModel,
                selectedDay: $selectedDay,
                selectedGroup: $selectedGroup,
                selectedTeacher: $selectedTeacher,
                selectedWeek: $viewModel.selectedWeek,
                englishTeachers: englishTeachers
            )
            .tabItem {
                Label("Расписание", systemImage: "calendar")
            }

            NavigationView {
                SettingsView(selectedGroup: $selectedGroup,
                             selectedTeacher: $selectedTeacher,
                             groups: groups,
                             englishTeachers: englishTeachers,
                             autoRefreshInterval: $autoRefreshInterval,
                             appTheme: $appTheme,
                             notificationSettings: notificationSettings,
                             authorizationStatus: $notificationAuthorizationStatus)
            }
            .tabItem {
                Label("Настройки", systemImage: "gear")
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .onAppear {
            selectedGroup = selectedGroupStored
            selectedTeacher = selectedTeacherStored
            autoRefreshInterval = autoRefreshIntervalStored
            appTheme = AppTheme(rawValue: appThemeStored) ?? .system
            
            notificationSettings.authorizationStatus { status in
                notificationAuthorizationStatus = status
            }

            if !selectedGroupStored.isEmpty {
                viewModel.selectedGroup = selectedGroupStored
                viewModel.fetchSchedule()
            }

            startAutoRefresh()
            startDayChangeTimer()
            checkShowDayChangeAlert()

            scheduleNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkShowDayChangeAlert()
            notificationSettings.authorizationStatus { status in
                notificationAuthorizationStatus = status
            }
            scheduleNotifications()
        }
        .onChange(of: selectedGroup) { newValue in
            selectedGroupStored = newValue
            viewModel.selectedGroup = newValue
            viewModel.fetchSchedule()
            startAutoRefresh()
            scheduleNotifications()
        }
        .onChange(of: selectedTeacher) { newValue in
            selectedTeacherStored = newValue
        }
        .onChange(of: autoRefreshInterval) { newValue in
            autoRefreshIntervalStored = newValue
            startAutoRefresh()
        }
        .onChange(of: appTheme) { newValue in
            appThemeStored = newValue.rawValue
        }
        .onChange(of: selectedDay) { _ in
            scheduleNotifications()
        }
        .onChange(of: notificationSettings.notificationsEnabled) { newValue in
            if newValue {
                notificationSettings.requestAuthorization { granted in
                    notificationAuthorizationStatus = granted ? .authorized : .denied
                    if granted {
                        scheduleNotifications()
                    } else {
                        removeAllNotifications()
                    }
                }
            } else {
                removeAllNotifications()
            }
        }
        .onChange(of: notificationSettings.notificationTime) { _ in
            scheduleNotifications()
        }
        .onDisappear {
            stopAutoRefresh()
            stopDayChangeTimer()
            removeAllNotifications()
        }
        .alert(isPresented: $showDayChangeAlert) {
            Alert(
                title: Text("Учебный день закончен"),
                message: Text("Переключить расписание на следующий день?"),
                primaryButton: .default(Text("Сменить")) {
                    switchToNextDay()
                },
                secondaryButton: .cancel(Text("Оставить"))
            )
        }
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        guard autoRefreshInterval > 0, !selectedGroup.isEmpty else { return }
        refreshTimerCancellable = Timer.publish(every: autoRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                viewModel.fetchSchedule()
                scheduleNotifications()
            }
    }

    private func stopAutoRefresh() {
        refreshTimerCancellable?.cancel()
        refreshTimerCancellable = nil
    }

    private func startDayChangeTimer() {
        dayChangeTimer?.invalidate()
        dayChangeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            checkShowDayChangeAlert()
        }
    }

    private func stopDayChangeTimer() {
        dayChangeTimer?.invalidate()
        dayChangeTimer = nil
    }

    private func checkShowDayChangeAlert() {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)

        let todayString: String
        switch currentWeekday {
        case 2: todayString = "ПН"
        case 3: todayString = "ВТ"
        case 4: todayString = "СР"
        case 5: todayString = "ЧТ"
        case 6: todayString = "ПТ"
        case 7: todayString = "СБ"
        case 1: todayString = "ВС"
        default: todayString = "ПН"
        }
        if selectedDay == todayString {
            var comp = calendar.dateComponents([.year, .month, .day], from: now)
            comp.hour = 20
            comp.minute = 0
            comp.second = 0
            if let switchTime = calendar.date(from: comp), now >= switchTime {
                showDayChangeAlert = true
            }
        }
    }

    private func switchToNextDay() {
        if let currentIndex = daysOfWeek.firstIndex(of: selectedDay) {
            let nextIndex = (currentIndex + 1) % daysOfWeek.count
            selectedDay = daysOfWeek[nextIndex]
            viewModel.selectedGroup = selectedGroupStored
            viewModel.fetchSchedule()
            scheduleNotifications()
        }
    }
    
    private func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func scheduleNotifications() {
        removeAllNotifications()
        guard notificationSettings.notificationsEnabled && !selectedGroup.isEmpty else { return }
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                DispatchQueue.main.async {
                    notificationAuthorizationStatus = settings.authorizationStatus
                }
                return
            }
            
            guard let nextLesson = getAppropriateNextLesson() else { return }
            
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            
            guard let lessonStartTime = dateFormatter.date(from: nextLesson.startTime) else { return }
            
            let now = Date()
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = calendar.component(.hour, from: lessonStartTime)
            components.minute = calendar.component(.minute, from: lessonStartTime)
            components.second = 0
            
            guard let lessonDateTime = calendar.date(from: components) else { return }
            
            let notificationTimeInterval = notificationSettings.notificationTime * 60
            let triggerDate = lessonDateTime.addingTimeInterval(-notificationTimeInterval)
            if triggerDate <= now {
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "Следующая пара"
            let audience = nextLesson.classroom ?? "Не указана"
            let subject = nextLesson.discipline
            content.body = "\(audience), \(subject)"
            content.sound = UNNotificationSound.default
            
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func getAppropriateNextLesson() -> Lesson? {
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"

        let englishSubjects = ["Английский для ИТ-специалистов", "Иностранный язык"]
        let lessonsForDay = viewModel.lessons.filter { $0.dayWeek == selectedDay }

        let filteredLessons = lessonsForDay.filter { lesson in
            if englishSubjects.contains(lesson.discipline) {
                if selectedTeacher.isEmpty {
                    return true
                }
                return lesson.teachers.values.contains(where: { $0.fio == selectedTeacher })
            }
            return true
        }

        if filteredLessons.isEmpty {
            return nil
        }

        let isToday: Bool = {
            let weekday = calendar.component(.weekday, from: now)
            let dayStr: String
            switch weekday {
            case 2: dayStr = "ПН"
            case 3: dayStr = "ВТ"
            case 4: dayStr = "СР"
            case 5: dayStr = "ЧТ"
            case 6: dayStr = "ПТ"
            case 7: dayStr = "СБ"
            case 1: dayStr = "ВС"
            default: dayStr = "ПН"
            }
            return dayStr == selectedDay
        }()

        if isToday {
            let upcomingLessons = filteredLessons.compactMap { lesson -> (Date, Lesson)? in
                guard let startTimeDate = dateFormatter.date(from: lesson.startTime) else {
                    return nil
                }
                let startHour = calendar.component(.hour, from: startTimeDate)
                let startMinute = calendar.component(.minute, from: startTimeDate)

                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = startHour
                components.minute = startMinute

                guard let lessonDateTime = calendar.date(from: components) else {
                    return nil
                }

                if lessonDateTime > now {
                    return (lessonDateTime, lesson)
                }
                return nil
            }
            .sorted(by: { $0.0 < $1.0 })

            return upcomingLessons.first?.1
        } else {
            let sortedLessons = filteredLessons.sorted { l1, l2 in
                dateFormatter.date(from: l1.startTime) ?? Date.distantFuture < dateFormatter.date(from: l2.startTime) ?? Date.distantFuture
            }
            return sortedLessons.first
        }
    }
}

struct ScheduleView: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @Binding var selectedDay: String
    @Binding var selectedGroup: String
    @Binding var selectedTeacher: String
    @Binding var selectedWeek: Int

    let englishTeachers: [String]

    private let groupTypeColorsLight: [String: Color] = [
        "Лекции": Color.green,
        "Практические занятия": Color.blue.opacity(0.2),
        "Консультация": Color.yellow,
        "Внеучебное мероприятие": Color.yellow,
        "Контрольная работа": Color.yellow,
        "Зачет": Color.red,
        "ППА": Color.purple
    ]

    private let groupTypeColorsDark: [String: Color] = [
        "Лекции": Color.green,
        "Практические занятия": Color.blue.opacity(0.5),
        "Консультация": Color.yellow.opacity(0.8),
        "Внеучебное мероприятие": Color.yellow.opacity(0.8),
        "Контрольная работа": Color.yellow.opacity(0.8),
        "Зачет": Color.red.opacity(0.8),
        "ППА": Color.purple.opacity(0.8)
    ]

    @Environment(\.colorScheme) var colorScheme

    @State private var showWeekPicker = false
    @State private var showDayPicker = false

    let daysOfWeek = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                HStack {
                    Button(action: {
                        showWeekPicker.toggle()
                    }) {
                        Text("\(weekRangeString(for: selectedWeek))")
                            .font(.title)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 0)
                            .background(Color(UIColor.systemBackground))
                            .foregroundColor(Color(UIColor.label))
                            .cornerRadius(8)
                    }
                    .actionSheet(isPresented: $showWeekPicker) {
                        ActionSheet(title: Text("Выберите неделю"), buttons: [
                            .default(Text(weekRangeString(for: -1))) { selectedWeek = -1; fetchSchedule() },
                            .default(Text(weekRangeString(for: 0))) { selectedWeek = 0; fetchSchedule() },
                            .default(Text(weekRangeString(for: 1))) { selectedWeek = 1; fetchSchedule() },
                            .default(Text(weekRangeString(for: 2))) { selectedWeek = 2; fetchSchedule() },
                            .cancel()
                        ])
                    }

                    Button(action: {
                        showDayPicker.toggle()
                    }) {
                        Text("\(selectedDay)")
                            .font(.title)
                            .fontWeight(.bold)
                            .frame(minWidth: 50, maxHeight: 15, alignment: .trailing)
                            .padding()
                            .background(Color(UIColor.systemBackground))
                            .foregroundColor(Color(UIColor.label))
                            .cornerRadius(8)
                    }
                    .actionSheet(isPresented: $showDayPicker) {
                        ActionSheet(title: Text("Выберите день"), buttons: [
                            .default(Text("Понедельник")) { selectedDay = "ПН"; fetchSchedule() },
                            .default(Text("Вторник")) { selectedDay = "ВТ"; fetchSchedule() },
                            .default(Text("Среда")) { selectedDay = "СР"; fetchSchedule() },
                            .default(Text("Четверг")) { selectedDay = "ЧТ"; fetchSchedule() },
                            .default(Text("Пятница")) { selectedDay = "ПТ"; fetchSchedule() },
                            .default(Text("Суббота")) { selectedDay = "СБ"; fetchSchedule() },
                            .default(Text("Воскресенье")) { selectedDay = "ВС"; fetchSchedule() },
                            .cancel()
                        ])
                    }
                }
                .padding(.horizontal)

                if viewModel.isLoading {
                    ProgressView("Загрузка...")
                        .padding()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        if let nextLesson = getAppropriateNextLesson() {
                            Text("Следующая пара:")
                                .font(.headline)
                                .padding(.horizontal)

                            nextLessonInfoView(lesson: nextLesson)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(getColor(for: nextLesson.groupType))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                        }

                        ForEach(filteredLessons(), id: \.id) { lesson in
                            lessonInfoView(lesson: lesson)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(getColor(for: lesson.groupType))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom)
                }
            }
            .onChange(of: selectedDay) { _ in
                fetchSchedule()
            }
            .onChange(of: selectedWeek) { _ in
                fetchSchedule()
            }
        }
    }

    private func fetchSchedule() {
        guard !selectedGroup.isEmpty else { return }
        viewModel.selectedGroup = selectedGroup
        viewModel.selectedWeek = selectedWeek
        viewModel.fetchSchedule()
    }

    private func lessonInfoView(lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(lesson.discipline)")
                .fontWeight(.semibold)
            Text("\(lesson.groupType)")
            Text("\(lesson.startTime) - \(lesson.endTime)")
            Text("Аудитория: \(lesson.classroom ?? "Не указана")")
            ForEach(lesson.teachers.values.sorted(by: { $0.fio < $1.fio }), id: \.id) { teacher in
                Text("Преподаватель: \(teacher.fio)")
            }
        }
    }

    private func nextLessonInfoView(lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(lesson.discipline)")
                .fontWeight(.semibold)
            Text("Аудитория: \(lesson.classroom ?? "Не указана")")
        }
    }

    private func filteredLessons() -> [Lesson] {
        let englishSubjects = ["Английский для ИТ-специалистов", "Иностранный язык"]

        let lessonsForDay = viewModel.lessons.filter { $0.dayWeek == selectedDay }

        return lessonsForDay.filter { lesson in
            if englishSubjects.contains(lesson.discipline) {
                if selectedTeacher.isEmpty {
                    return true
                }
                return lesson.teachers.values.contains(where: { $0.fio == selectedTeacher })
            }
            return true
        }
    }

    private func getColor(for groupType: String) -> Color {
        if colorScheme == .dark {
            return groupTypeColorsDark[groupType] ?? Color(UIColor.systemBackground)
        } else {
            return groupTypeColorsLight[groupType] ?? Color(UIColor.systemBackground)
        }
    }

    private func getAppropriateNextLesson() -> Lesson? {
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"

        let englishSubjects = ["Английский для ИТ-специалистов", "Иностранный язык"]
        let lessonsForDay = viewModel.lessons.filter { $0.dayWeek == selectedDay }

        let filteredLessons = lessonsForDay.filter { lesson in
            if englishSubjects.contains(lesson.discipline) {
                if selectedTeacher.isEmpty {
                    return true
                }
                return lesson.teachers.values.contains(where: { $0.fio == selectedTeacher })
            }
            return true
        }

        if filteredLessons.isEmpty {
            return nil
        }

        let isToday: Bool = {
            let weekday = calendar.component(.weekday, from: now)
            let dayStr: String
            switch weekday {
            case 2: dayStr = "ПН"
            case 3: dayStr = "ВТ"
            case 4: dayStr = "СР"
            case 5: dayStr = "ЧТ"
            case 6: dayStr = "ПТ"
            case 7: dayStr = "СБ"
            case 1: dayStr = "ВС"
            default: dayStr = "ПН"
            }
            return dayStr == selectedDay
        }()

        if isToday {
            let upcomingLessons = filteredLessons.compactMap { lesson -> (Date, Lesson)? in
                guard let startTimeDate = dateFormatter.date(from: lesson.startTime) else {
                    return nil
                }
                let startHour = calendar.component(.hour, from: startTimeDate)
                let startMinute = calendar.component(.minute, from: startTimeDate)

                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = startHour
                components.minute = startMinute

                guard let lessonDateTime = calendar.date(from: components) else {
                    return nil
                }

                if lessonDateTime > now {
                    return (lessonDateTime, lesson)
                }
                return nil
            }
            .sorted(by: { $0.0 < $1.0 })

            return upcomingLessons.first?.1
        } else {
            let sortedLessons = filteredLessons.sorted { l1, l2 in
                dateFormatter.date(from: l1.startTime) ?? Date.distantFuture < dateFormatter.date(from: l2.startTime) ?? Date.distantFuture
            }
            return sortedLessons.first
        }
    }

    private func weekRangeString(for offset: Int) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 7 - calendar.firstWeekday) % 7
        guard let mondayThisWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else {
            return ""
        }

        guard let targetMonday = calendar.date(byAdding: .weekOfYear, value: offset, to: mondayThisWeek) else {
            return ""
        }

        guard let targetSunday = calendar.date(byAdding: .day, value: 6, to: targetMonday) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d.MM"
        let startString = formatter.string(from: targetMonday)
        let endString = formatter.string(from: targetSunday)
        return "\(startString)-\(endString)"
    }
}

struct SettingsView: View {
    @Binding var selectedGroup: String
    @Binding var selectedTeacher: String
    let groups: [String]
    let englishTeachers: [String]

    @Binding var autoRefreshInterval: Double
    @Binding var appTheme: AppTheme
    
    @ObservedObject var notificationSettings: NotificationSettings
    @Binding var authorizationStatus: UNAuthorizationStatus
    
    var body: some View {
        List {
            NavigationLink(destination: SettingsSelectionView(selectedGroup: $selectedGroup,
                                                             selectedTeacher: $selectedTeacher,
                                                             groups: groups,
                                                             englishTeachers: englishTeachers)) {
                Label("Настройки отображения", systemImage: "person.3")
            }

            NavigationLink(destination: SettingsAutoRefreshView(autoRefreshInterval: $autoRefreshInterval)) {
                Label("Автообновление расписания", systemImage: "arrow.clockwise")
            }

            NavigationLink(destination: SettingsThemeView(appTheme: $appTheme)) {
                Label("Тема приложения", systemImage: "moon.circle")
            }
            
            NavigationLink(destination: NotificationSettingsView(notificationSettings: notificationSettings, authorizationStatus: $authorizationStatus)) {
                Label("Настройки уведомлений", systemImage: "bell")
            }

            NavigationLink(destination: SettingsInfoView()) {
                Label("Информация", systemImage: "info.circle")
            }
        }
        .navigationTitle("Настройки")
        .listStyle(InsetGroupedListStyle())
    }
}

enum AutoRefreshOption: Double, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case sixtyMinutes = 3600
    case disabled = 0

    var id: Double { self.rawValue }

    var description: String {
        switch self {
        case .oneMinute: return "1 мин"
        case .fiveMinutes: return "5 мин"
        case .tenMinutes: return "10 мин"
        case .thirtyMinutes: return "30 мин"
        case .sixtyMinutes: return "60 мин"
        case .disabled: return "Не обновлять"
        }
    }
}

struct SettingsAutoRefreshView: View {
    @Binding var autoRefreshInterval: Double

    private let options = AutoRefreshOption.allCases

    var body: some View {
        Form {
            Section(header: Text("Интервал автообновления")) {
                Picker("Интервал", selection: $autoRefreshInterval) {
                    ForEach(options) { option in
                        Text(option.description).tag(option.rawValue)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 150)
            }
            Section {
                Text("Выберите интервал, через который будет обновляться расписание.\n\"Не обновлять\" отключает автообновление.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.vertical)
            }
        }
        .navigationTitle("Автообновление")
    }
}

struct SettingsThemeView: View {
    @Binding var appTheme: AppTheme

    var body: some View {
        Form {
            Section(header: Text("Выберите тему приложения")) {
                Picker("Тема", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.description).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(height: 150)
            }
        }
        .navigationTitle("Тема")
    }
}

struct SettingsSelectionView: View {
    @Binding var selectedGroup: String
    @Binding var selectedTeacher: String
    let groups: [String]
    let englishTeachers: [String]

    var body: some View {
        Form {
            Section(header: Text("Группа")) {
                Picker("Группа", selection: $selectedGroup) {
                    ForEach(groups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .foregroundColor(.black)
            }
            Section(header: Text("Преподаватель английского языка")) {
                Picker("Преподаватель", selection: $selectedTeacher) {
                    Text("Все преподаватели").tag("")
                    ForEach(englishTeachers, id: \.self) { teacher in
                        Text(teacher).tag(teacher)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .foregroundColor(.black)
            }
        }
        .navigationTitle("Отображение")
    }
}

struct SettingsInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Информация о приложении")
                .font(.headline)
                .padding(.bottom, 5)
            Text("Разработчик: Dvolj")
            Text("Версия: 1.0")
            Spacer()
        }
        .padding()
        .navigationTitle("Информация")
    }
}

// Added Missing NotificationSettingsView
struct NotificationSettingsView: View {
    @ObservedObject var notificationSettings: NotificationSettings
    @Binding var authorizationStatus: UNAuthorizationStatus
    
    @State private var showSettingsAlert = false

    var body: some View {
        Form {
            Section(header: Text("Уведомления")) {
                Toggle("Включить уведомления", isOn: $notificationSettings.notificationsEnabled)
                    .onChange(of: notificationSettings.notificationsEnabled) { enabled in
                        if enabled {
                            notificationSettings.requestAuthorization { granted in
                                if !granted {
                                    notificationSettings.notificationsEnabled = false
                                    showSettingsAlert = true
                                }
                                authorizationStatus = granted ? .authorized : .denied
                            }
                        }
                    }
                
                if notificationSettings.notificationsEnabled {
                    Picker("Время уведомления (минуты до начала)", selection: $notificationSettings.notificationTime) {
                        ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                            Text("\(minutes) мин").tag(Double(minutes))
                        }
                    }
                }
            }
            
            if authorizationStatus == .denied {
                Section {
                    Button("Открыть настройки приложения") {
                        guard let url = URL(string: UIApplication.openSettingsURLString),
                              UIApplication.shared.canOpenURL(url)
                        else { return }
                        UIApplication.shared.open(url)
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Настройки уведомлений")
        .alert(isPresented: $showSettingsAlert) {
            Alert(title: Text("Разрешение на уведомления отклонено"),
                  message: Text("Пожалуйста, разрешите уведомления в настройках приложения."),
                  dismissButton: .default(Text("Ок")))
        }
    }
}

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
