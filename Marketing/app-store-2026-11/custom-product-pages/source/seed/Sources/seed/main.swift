import Foundation
import FavWidgetsCore

var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
let today = DayKey(Date(), calendar: cal)
let thisMonth = MonthKey.current(calendar: cal)
func at(_ day: DayKey, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day.date(calendar: cal))! }
var docs: [String: Any] = [:]
func put<M: WidgetModel>(_ id: String, _ model: M, schema: Int = 1) {
  let data = try! WidgetDocumentCodec.encode(model)
  docs[id] = ["payload": String(data: data, encoding: .utf8)!, "schemaVersion": schema]
}
func shard(_ w: String, _ d: DayKey) -> String { WidgetShardPlanner.shardId(widgetId: w, day: d) }
var rng = SystemRandomNumberGenerator()

// Wake Up
let jazz = MusicStation(name: "Morning Jazz Radio", link: "https://www.pandora.com/station/play/4185340618512341")
let happy = MusicStation(name: "Wake Up Happy", link: "https://open.spotify.com/playlist/37i9dQZF1DX0UrRvztWcAU")
let hits = MusicStation(name: "Today's Hits", link: "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb")
put("wakeup", AlarmClockSettings(alarms: [
  WakeAlarm(minutes: 6*60+30, days: [2,3,4,5,6], label: "Gym", stationId: happy.id, snoozeMinutes: 9),
  WakeAlarm(minutes: 7*60+15, days: [2,3,4,5,6], label: "Work", stationId: hits.id, snoozeMinutes: 9),
  WakeAlarm(minutes: 8*60+30, days: [1,7], label: "Weekend", stationId: jazz.id, snoozeMinutes: 10)
], stations: [happy, jazz, hits]), schema: AlarmClockSettings.schemaVersion)

// Sleep Sounds
let rainy = SleepMix(name: "Rainy night", levels: ["rain": 0.8, "thunder": 0.3, "fan": 0.2])
let ocean = SleepMix(name: "Beach house", levels: ["ocean": 0.75, "wind": 0.25])
let campfire = SleepMix(name: "Campfire", levels: ["fire": 0.7, "crickets": 0.4])
var ss = SleepSoundsSettings(mixes: [rainy, ocean, campfire], lastLevels: rainy.levels, lastMixName: rainy.name)
ss.bedtime = SleepBedtime(enabled: true, minutes: 22*60+30, mixId: rainy.id)
put("sleepsounds", ss)
var ssm = SleepSoundsMonth()
for back in 1...5 { let d = today.adding(days: -back, calendar: cal); ssm.sessions.append(SleepSession(startedAt: at(d, 22, 35), seconds: 3600 + Int.random(in: 0...1800), mixName: [rainy.name, ocean.name][back % 2])) }
put(shard("sleepsounds", today), ssm)

// Water
var water = WaterLog(goalCups: 8, reminders: WaterReminders(enabled: true, intervalHours: 2))
for back in 1...40 { water.setCups(back == 23 ? 6 : [8,9,8,8,10,8,9][back % 7], on: today.adding(days: -back, calendar: cal), calendar: cal) }
water.setCups(6, on: today, calendar: cal)
put("water", water, schema: WaterLog.schemaVersion)

// Meds
let vitD = Med(name: "Vitamin D", dose: "1000 IU", times: [8*60])
let lis = Med(name: "Lisinopril", dose: "10 mg", times: [8*60])
let mag = Med(name: "Magnesium", dose: "400 mg", times: [21*60])
put("meds", MedSettings(meds: [vitD, lis, mag]), schema: MedSettings.schemaVersion)
var medMonths: [String: MedMonth] = [:]
for back in 0...34 {
  let d = today.adding(days: -back, calendar: cal)
  for med in [vitD, lis, mag] where !(back == 0 && med.id == mag.id) {
    let key = shard("meds", d)
    medMonths[key, default: MedMonth()].record(MedDose(medId: med.id, day: d, slot: med.times[0], status: (back == 7 && med.id == mag.id) ? .skipped : .taken, at: at(d, med.times[0]/60, 4)))
  }
}
for (k, v) in medMonths { put(k, v, schema: MedSettings.schemaVersion) }

// Habits
let hs = [Habit(name: "Read 20 minutes", symbolName: "book.fill", createdAt: at(today.adding(days: -60, calendar: cal), 9, 0)),
          Habit(name: "Stretch", symbolName: "figure.cooldown", createdAt: at(today.adding(days: -60, calendar: cal), 9, 0)),
          Habit(name: "10,000 steps", symbolName: "figure.walk", createdAt: at(today.adding(days: -60, calendar: cal), 9, 0)),
          Habit(name: "No phone in bed", symbolName: "moon.zzz.fill", createdAt: at(today.adding(days: -60, calendar: cal), 9, 0)),
          Habit(name: "Meditate 5 minutes", symbolName: "brain.head.profile", createdAt: at(today.adding(days: -60, calendar: cal), 9, 0)),
          Habit(name: "Call Mom", symbolName: "phone.fill", schedule: .weekdays([1]), createdAt: at(today.adding(days: -60, calendar: cal), 9, 0))]
var hl = HabitLog(habits: hs)
for back in 1...45 { for (i, h) in hs.enumerated() where !([31, 38].contains(back + i * 2)) { hl.setDone(true, habitId: h.id, on: today.adding(days: -back, calendar: cal), calendar: cal) } }
hl.setDone(true, habitId: hs[0].id, on: today, calendar: cal); hl.setDone(true, habitId: hs[1].id, on: today, calendar: cal)
put("habits", hl)

// Calories
var calSet = CalorieSettings(dailyGoalKcal: 2100, macroGoals: MacroTotals(kcal: 2100, protein: 150, carbs: 220, fat: 70))
var cm = CalorieMonth()
let foods: [(String, Int, Double, Double, Double, Int)] = [("Greek yogurt & berries", 220, 18, 28, 4, 8), ("Coffee with oat milk", 60, 1, 8, 3, 8), ("Turkey avocado sandwich", 480, 32, 42, 19, 12), ("Apple", 95, 0.5, 25, 0.3, 15), ("Grilled salmon & rice", 610, 42, 58, 21, 19)]
for back in 0...6 { let d = today.adding(days: -back, calendar: cal); for f in foods where back > 0 || f.5 < 16 { let e = FoodEntry(name: f.0, kcal: f.1, protein: f.2, carbs: f.3, fat: f.4, loggedAt: at(d, f.5, 10)); cm.add(e, on: d); calSet.noteRecent(e) } }
put("calories", calSet); put(shard("calories", today), cm)

// Run
let raw = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
let pts = raw.split(separator: ";").map { p -> (Double, Double) in let a = p.split(separator: ",").map { Double($0)! }; return (a[0], a[1]) }
var meters = 0.0; for i in 1..<pts.count { meters += RunGeo.distance(pts[i-1].0, pts[i-1].1, pts[i].0, pts[i].1) }
var rm = RunMonth()
for (back, laps) in [(1, 1.0), (3, 1.0), (5, 1.0)] {
  let d = today.adding(days: -back, calendar: cal); let secs = meters * laps / 1609.34 * (558 + Double(back * 4))
  let miles = meters / 1609.34
  rm.runs.append(RunRecord(startedAt: at(d, 6, 40), endedAt: at(d, 6, 40).addingTimeInterval(secs + 40), movingSeconds: secs, distanceMeters: meters,
    route: RunGeo.encode(pts), splitsMile: Array(repeating: secs / miles, count: Int(miles)), splitsKm: Array(repeating: secs / (meters/1000), count: Int(meters/1000)),
    efforts: ["1mi": secs / miles - 6], calories: RunMath.calories(meters: meters, weightKg: 72), title: "Freedom Park loop"))
}
put("run", RunSettings(unit: .miles, weightKg: 72), schema: RunSettings.schemaVersion); put(shard("run", today), rm, schema: RunSettings.schemaVersion)

// Workouts
var wm = WorkoutMonth()
let plans: [(String, [(String, Int, Double)])] = [
  ("Push day", [("bench_press", 8, 185), ("overhead_press", 8, 105), ("incline_db_press", 10, 60), ("tricep_pushdown", 12, 50)]),
  ("Leg day", [("squat", 6, 225), ("romanian_deadlift", 8, 185), ("leg_press", 10, 360), ("calf_raise", 15, 120)]),
  ("Pull day", [("deadlift", 5, 275), ("lat_pulldown", 10, 140), ("barbell_row", 8, 155), ("bicep_curl", 12, 35)])]
for (i, back) in [6, 4, 2, 0].enumerated() {
  let d = today.adding(days: -back, calendar: cal); let p = plans[i % 3]; var t = at(d, 17, 30); var sets: [SetEntry] = []
  for ex in p.1 { for s in 0..<3 { t = t.addingTimeInterval(150); sets.append(SetEntry(exerciseId: ex.0, reps: ex.1, weight: ex.2 + (back == 0 ? 5 : 0) - Double(s == 2 ? 0 : 0), completedAt: t)) } }
  wm.sessions.append(WorkoutSession(name: p.0, startedAt: at(d, 17, 30), endedAt: t.addingTimeInterval(120), sets: sets))
}
put("workouts", WorkoutSettings(), schema: 7); put(shard("workouts", today), wm, schema: 7)

print(String(data: try! JSONSerialization.data(withJSONObject: docs, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
