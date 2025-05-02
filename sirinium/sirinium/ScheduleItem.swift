import Foundation

// Модель для преподавателя
struct Teacher: Codable {
    var id: String
    var lastName: String?
    var firstNameOne: String?
    var firstName: String?
    var middleName: String?
    var middleNameOne: String?
    var fio: String
    var departmentFio: String?
    var department: String?
}

// Модель для урока
struct Lesson: Codable, Identifiable {
    var id: UUID { UUID() } // Генерируем уникальный идентификатор
    var date: String
    var dayWeek: String
    var startTime: String
    var endTime: String
    var discipline: String
    var groupType: String
    var address: String?
    var classroom: String? // Аудитория
    var comment: String?
    var place: String?
    var teachers: [String: Teacher] // Словарь
    var urlOnline: String?
    var group: String
    var numberPair: Int? // Номер занятия
    var color: String
    var code: String
}
