import Foundation
import Combine

class ScheduleViewModel: ObservableObject {
    @Published var lessons: [Lesson] = []
    @Published var selectedGroup: String = ""
    @Published var selectedWeek: Int = 0
    @Published var isLoading: Bool = false // Для отслеживания состояния загрузки
    
    // Определяем порядок дней недели
    private let daysOfWeekOrder: [String] = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
    
    func fetchSchedule() {
        guard !selectedGroup.isEmpty else {
            print("Группа не указана")
            return
        }
        
        // Кодируем номер группы для использования в URL
        guard let encodedGroup = selectedGroup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Ошибка кодирования группы")
            return
        }
        
        // Получаем номер текущей недели
        let currentWeek = getCurrentWeekOffset()
        let urlString = "https://api.eralas.ru/api/schedule?group=\(encodedGroup)&week=\(currentWeek)"
        print("Fetching schedule from URL: \(urlString)") // Для отладки
        
        guard let url = URL(string: urlString) else {
            print("Неверный URL")
            return
        }
        
        isLoading = true // Устанавливаем состояние загрузки
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching schedule: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false // Сбрасываем состояние загрузки
                }
                return
            }
            
            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.isLoading = false // Сбрасываем состояние загрузки
                }
                return
            }
            
            do {
                // Декодируем массив уроков
                let decodedData = try JSONDecoder().decode([Lesson].self, from: data)
                DispatchQueue.main.async {
                    // Сортируем занятия по дню недели и номеру занятия
                    self.lessons = decodedData.sorted {
                        // Сравниваем дни недели по индексу
                        let day1Index = self.daysOfWeekOrder.firstIndex(of: $0.dayWeek.trimmingCharacters(in: .whitespaces)) ?? Int.max
                        let day2Index = self.daysOfWeekOrder.firstIndex(of: $1.dayWeek.trimmingCharacters(in: .whitespaces)) ?? Int.max
                        
                        if day1Index == day2Index {
                            // Если дни одинаковые, сравниваем номера занятий
                            return ($0.numberPair ?? 0) < ($1.numberPair ?? 0)
                        }
                        return day1Index < day2Index
                    }
                    print("Загружено \(self.lessons.count) уроков") // Отладка
                    self.isLoading = false // Сбрасываем состояние загрузки
                }
            } catch {
                print("Error decoding JSON: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false // Сбрасываем состояние загрузки
                }
            }
        }.resume()
    }
    
    private func getCurrentWeekOffset() -> Int {
        // Возвращаем значение выбранной недели
        return selectedWeek
    }
}
