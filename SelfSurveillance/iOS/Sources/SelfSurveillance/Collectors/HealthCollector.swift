// MARK: - HealthCollector.swift
// Reads HealthKit samples in background delivery mode.
// Observes: steps, heart rate, sleep, respiratory rate, blood oxygen,
// resting heart rate, HRV, active energy, walking speed, headphone audio levels.
//
// Data is read as raw HKQuantitySample objects — unprocessed by any app.

import HealthKit

public final class HealthCollector {

    public static let shared = HealthCollector()
    private let store = HKHealthStore()
    private var queries: [HKQuery] = []

    // All quantity types we observe
    private let observedTypes: [HKQuantityTypeIdentifier] = [
        .stepCount,
        .heartRate,
        .restingHeartRate,
        .heartRateVariabilitySDNN,
        .respiratoryRate,
        .oxygenSaturation,
        .activeEnergyBurned,
        .basalEnergyBurned,
        .walkingSpeed,
        .walkingStepLength,
        .walkingAsymmetryPercentage,
        .walkingDoubleSupportPercentage,
        .headphoneAudioExposure,
        .environmentalAudioExposure,
        .bodyMass,
        .bodyMassIndex,
        .height,
        .bodyFatPercentage,
        .bloodPressureSystolic,
        .bloodPressureDiastolic,
        .bloodGlucose,
        .bodyTemperature,
    ]

    private let observedCategoryTypes: [HKCategoryTypeIdentifier] = [
        .sleepAnalysis,
        .mindfulSession,
        .handwashingEvent,
        .menstrualFlow,
        .spotting,
        .irregularHeartRhythmEvent,
        .lowHeartRateEvent,
        .highHeartRateEvent,
    ]

    private init() {}

    public func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        var readTypes: Set<HKObjectType> = []
        for id in observedTypes {
            if let t = HKObjectType.quantityType(forIdentifier: id) { readTypes.insert(t) }
        }
        for id in observedCategoryTypes {
            if let t = HKObjectType.categoryType(forIdentifier: id) { readTypes.insert(t) }
        }

        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] granted, _ in
            guard granted else { return }
            self?.setupObservers()
        }
    }

    private func setupObservers() {
        // Quantity types
        for id in observedTypes {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] query, completion, error in
                self?.fetchRecent(type: type, identifier: id.rawValue)
                completion()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            queries.append(query)
        }

        // Category types
        for id in observedCategoryTypes {
            guard let type = HKObjectType.categoryType(forIdentifier: id) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] query, completion, error in
                self?.fetchRecentCategory(type: type, identifier: id.rawValue)
                completion()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            queries.append(query)
        }
    }

    private func fetchRecent(type: HKQuantityType, identifier: String) {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: recentPredicate(),
            limit: 20,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in
            guard let samples = samples as? [HKQuantitySample] else { return }
            for sample in samples {
                let unit = self.preferredUnit(for: type)
                let value = sample.quantity.doubleValue(for: unit)
                ImmutableLogStore.shared.append(
                    source: .health,
                    category: .health,
                    appBundleID: sample.sourceRevision.source.bundleIdentifier,
                    appDisplayName: sample.sourceRevision.source.name,
                    eventType: "healthSample:\(identifier)",
                    payload: .healthSample(HealthSamplePayload(
                        quantityType: identifier,
                        value: value,
                        unit: unit.unitString,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sourceApp: sample.sourceRevision.source.name,
                        device: sample.device?.name,
                        metadata: sample.metadata?.compactMapValues { "\($0)" }
                    ))
                )
            }
        }
        store.execute(query)
    }

    private func fetchRecentCategory(type: HKCategoryType, identifier: String) {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: recentPredicate(),
            limit: 20,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in
            guard let samples = samples as? [HKCategorySample] else { return }
            for sample in samples {
                ImmutableLogStore.shared.append(
                    source: .health,
                    category: .health,
                    appBundleID: sample.sourceRevision.source.bundleIdentifier,
                    appDisplayName: sample.sourceRevision.source.name,
                    eventType: "healthCategory:\(identifier)",
                    payload: .healthSample(HealthSamplePayload(
                        quantityType: identifier,
                        value: Double(sample.value),
                        unit: nil,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sourceApp: sample.sourceRevision.source.name,
                        device: sample.device?.name,
                        metadata: sample.metadata?.compactMapValues { "\($0)" }
                    ))
                )
            }
        }
        store.execute(query)
    }

    private func recentPredicate() -> NSPredicate {
        let cutoff = Date().addingTimeInterval(-3600)   // Last hour
        return HKQuery.predicateForSamples(withStart: cutoff, end: nil, options: .strictStartDate)
    }

    private func preferredUnit(for type: HKQuantityType) -> HKUnit {
        switch HKQuantityTypeIdentifier(rawValue: type.identifier) {
        case .heartRate, .restingHeartRate:                  return HKUnit(from: "count/min")
        case .stepCount, .activeEnergyBurned, .basalEnergyBurned: return .count()
        case .oxygenSaturation, .bodyFatPercentage:          return .percent()
        case .bodyMass:                                      return .gramUnit(with: .kilo)
        case .height:                                        return .meterUnit(with: .centi)
        case .bloodGlucose:                                  return HKUnit(from: "mg/dL")
        case .walkingSpeed:                                  return HKUnit(from: "km/hr")
        case .headphoneAudioExposure, .environmentalAudioExposure: return HKUnit(from: "dBASPL")
        case .bodyTemperature:                               return .degreeCelsius()
        case .heartRateVariabilitySDNN:                      return HKUnit(from: "ms")
        case .respiratoryRate:                               return HKUnit(from: "count/min")
        default:                                             return .count()
        }
    }

    public func stop() {
        queries.forEach { store.stop($0) }
        queries.removeAll()
    }
}
