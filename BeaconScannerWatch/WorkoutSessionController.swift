//
//  WorkoutSessionController.swift
//  BeaconScannerWatch
//

import Foundation
import HealthKit

/// Owns the HKWorkoutSession that keeps the app running with the wrist down.
/// HealthKit completion handlers arrive on arbitrary queues; the session
/// reference is guarded by `lock` so start/stop can race safely.
nonisolated final class WorkoutSessionController: @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let lock = NSLock()
    private var session: HKWorkoutSession?

    func start(status: @escaping @Sendable (String) -> Void) {
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: shareTypes, read: nil) { [weak self] granted, error in
            guard let self else { return }
            guard granted, error == nil else {
                status("HealthKit denied — screen may sleep")
                return
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .functionalStrengthTraining
            configuration.locationType = .indoor
            do {
                let session = try HKWorkoutSession(healthStore: self.healthStore, configuration: configuration)
                session.startActivity(with: Date())
                self.lock.lock()
                self.session = session
                self.lock.unlock()
                status("Workout session active — scanning")
            } catch {
                status("Workout session failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.end()
    }
}
