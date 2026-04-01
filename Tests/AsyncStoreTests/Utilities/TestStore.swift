//
//  TestStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

@testable import AsyncStore
import Foundation

public enum TestError: Error, Equatable {
    case test
}

public struct TestState: Sendable, Equatable {
    public var ints: [Int]
    public var strings: [String]
    public var error: TestError?
    
    public init(ints: [Int] = [], strings: [String] = [], error: TestError? = .none) {
        self.ints = ints
        self.strings = strings
        self.error = error
    }
}

public enum TestTask: Hashable, Sendable {
    case one
}

public typealias TestStore = AsyncStore<TestState, TestTask>

public extension TestStore {
    @MainActor
    convenience init(environment: AsyncStoreEnvironmentValues = .shared) {
        self.init(state: .init(), environment: environment)
    }
    
    func appendIntTask(value: Int, after duration: Duration) async throws -> Effect {
        try await Task.sleep(for: duration)
        return .append(value, to: \.ints)
    }
}

public enum TestStoreRepositoryKey: AsyncStoreRepositoryKey {
    public typealias State = TestState
    public typealias TaskIdentifier = TestTask
}

public extension AsyncStoreRepository {
    var testStore: TestStore {
        get { self[TestStoreRepositoryKey.self] }
        set { self[TestStoreRepositoryKey.self] = newValue }
    }
}
