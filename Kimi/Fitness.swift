import Foundation
import CoreMotion
import HealthKit
import UserNotifications

/// The trainer's data: steps from the iPhone's motion chip, body data from the Health app, the daily step goal
/// and the evening «сколько осталось» notification.
@MainActor
final class Fitness: ObservableObject {
    static let shared = Fitness()

    @Published private(set) var today: Int?
    @Published private(set) var goal = UserDefaults.standard.integer(forKey: "stepGoal")   // 0: no goal yet

    private let pedometer = CMPedometer()
    private let health = HKHealthStore()
    struct Problem: LocalizedError { let errorDescription: String? }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in [HKQuantityTypeIdentifier.stepCount, .bodyMass, .height, .restingHeartRate, .activeEnergyBurned] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(sleep) }
        return s
    }

    /// Asks iOS for motion and Health access. Steps are enough to work; Health is a bonus.
    func authorize() async -> String? {
        if HKHealthStore.isHealthDataAvailable() {
            try? await health.requestAuthorization(toShare: [], read: readTypes)
        }
        guard CMPedometer.isStepCountingAvailable() else { return "Этот iPhone не считает шаги." }
        do {
            _ = try await steps(from: Calendar.current.startOfDay(for: Date()), to: Date())
            await refresh()
            return nil
        } catch {
            return "Разрешите Kimy «Движение и фитнес»: Настройки → Kimy."
        }
    }

    // MARK: steps

    private func steps(from: Date, to: Date) async throws -> Int {
        try await withCheckedThrowingContinuation { c in
            pedometer.queryPedometerData(from: from, to: to) { data, error in
                if let data = data { c.resume(returning: data.numberOfSteps.intValue) } else { c.resume(throwing: error ?? Problem(errorDescription: "Нет данных о шагах.")) }
            }
        }
    }

    /// Steps per day, newest last (the motion chip keeps 7 days).
    func days(_ n: Int) async throws -> [(day: Date, steps: Int)] {
        let cal = Calendar.current, start = cal.startOfDay(for: Date())
        var out: [(Date, Int)] = []
        for back in stride(from: min(max(n, 1), 7) - 1, through: 0, by: -1) {
            let from = cal.date(byAdding: .day, value: -back, to: start)!
            let to = back == 0 ? Date() : cal.date(byAdding: .day, value: 1, to: from)!
            out.append((from, try await steps(from: from, to: to)))
        }
        return out
    }

    func report(days n: Int) async throws -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, EE"
        let list = try await days(n)
        let lines = list.map { "\(f.string(from: $0.day)): \($0.steps) шагов" + (goal > 0 ? ($0.steps >= goal ? " ✓" : " (цель \(goal))") : "") }
        return lines.joined(separator: "\n") + (goal > 0 ? "\nЦель: \(goal) шагов в день." : "\nЦель по шагам не задана.")
    }

    // MARK: goal and the evening check

    func setGoal(_ n: Int) async throws -> String {
        guard (1000...50000).contains(n) else { throw Problem(errorDescription: "Цель должна быть от 1 000 до 50 000 шагов.") }
        goal = n
        UserDefaults.standard.set(n, forKey: "stepGoal")
        let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        await refresh()
        return allowed ? "Цель \(n) шагов. Каждый вечер в 20:00 Kimy напомнит, сколько осталось."
            : "Цель \(n) шагов сохранена, но уведомления выключены: Настройки → Kimy → Уведомления."
    }

    /// Today's steps for the home card, and tonight's notification rewritten with the real numbers.
    func refresh() async {
        guard CMPedometer.isStepCountingAvailable(),
              let n = try? await steps(from: Calendar.current.startOfDay(for: Date()), to: Date()) else { return }
        today = n
        guard goal > 0 else { return }
        let center = UNUserNotificationCenter.current()
        // shortcut: the evening text is as fresh as the last app launch; the next 6 evenings get a generic nudge
        for day in 0..<7 {
            let content = UNMutableNotificationContent()
            content.title = "Шаги за сегодня"
            content.body = day == 0
                ? (n >= goal ? "Цель \(goal) выполнена: уже \(n) шагов 👏" : "Пройдено \(n) из \(goal). Осталось \(goal - n) — короткая прогулка закроет цель.")
                : "Цель — \(goal) шагов. Загляните в Kimy, чтобы проверить прогресс."
            content.sound = .default
            var when = Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.date(byAdding: .day, value: day, to: Date())!)
            when.hour = 20
            when.minute = 0
            if day == 0, Calendar.current.component(.hour, from: Date()) >= 20 { continue }
            center.add(UNNotificationRequest(identifier: "steps-\(day)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)),
                       withCompletionHandler: nil)
        }
    }

    // MARK: Health app

    func summary() async -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "Приложение «Здоровье» недоступно." }
        var lines: [String] = []
        func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ label: String, _ fmt: String) async {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
            let sample: HKQuantitySample? = await withCheckedContinuation { c in
                let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, s, _ in
                    c.resume(returning: s?.first as? HKQuantitySample)
                }
                health.execute(q)
            }
            if let v = sample?.quantity.doubleValue(for: unit) { lines.append("\(label): \(String(format: fmt, v))") }
        }
        await latest(.bodyMass, .gramUnit(with: .kilo), "Вес", "%.1f кг")
        await latest(.height, .meterUnit(with: .centi), "Рост", "%.0f см")
        await latest(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), "Пульс покоя", "%.0f уд/мин")

        let cal = Calendar.current, dayStart = cal.startOfDay(for: Date())
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let kcal: Double? = await withCheckedContinuation { c in
                let q = HKStatisticsQuery(quantityType: energy, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: dayStart, end: Date()),
                                          options: .cumulativeSum) { _, s, _ in c.resume(returning: s?.sumQuantity()?.doubleValue(for: .kilocalorie())) }
                health.execute(q)
            }
            if let kcal = kcal { lines.append("Активные калории сегодня: \(Int(kcal)) ккал") }
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let since = cal.date(byAdding: .hour, value: -18, to: dayStart)!
            let samples: [HKCategorySample] = await withCheckedContinuation { c in
                let q = HKSampleQuery(sampleType: sleepType, predicate: HKQuery.predicateForSamples(withStart: since, end: Date()), limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, s, _ in c.resume(returning: (s as? [HKCategorySample]) ?? []) }
                health.execute(q)
            }
            let asleep = samples.filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue && $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if asleep > 0 { lines.append(String(format: "Сон прошлой ночью: %.1f ч", asleep / 3600)) }
        }
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        let workouts: [HKWorkout] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForSamples(withStart: weekAgo, end: Date()), limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, s, _ in c.resume(returning: (s as? [HKWorkout]) ?? []) }
            health.execute(q)
        }
        if !workouts.isEmpty {
            lines.append("Тренировок за 7 дней: \(workouts.count), всего \(Int(workouts.reduce(0) { $0 + $1.duration } / 60)) мин")
        }
        if let n = today { lines.append("Шаги сегодня: \(n)" + (goal > 0 ? " из \(goal)" : "")) }
        return lines.isEmpty
            ? "В «Здоровье» нет данных или Kimy не дали доступ: Настройки → Здоровье → Доступ к данным → Kimy. Спроси вес, рост и возраст у владельца."
            : lines.joined(separator: "\n")
    }
}
