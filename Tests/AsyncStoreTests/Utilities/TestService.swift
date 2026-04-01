//
//  TestService.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import AsyncStore
import Foundation

public protocol TestServiceProvider: Sendable {
    func getInts() async throws -> [Int]
}

// MARK: Empty

public struct EmptyTestService: TestServiceProvider {
    public func getInts() async throws -> [Int] {
        return []
    }
}

public extension TestServiceProvider where Self == EmptyTestService {
    static var empty: Self { .init() }
}

// MARK: Mock

public struct MockTestService: TestServiceProvider {
    private let ints: [Int]
    
    init(ints: [Int]) {
        self.ints = ints
    }
    
    public func getInts() async throws -> [Int] {
        return ints
    }
}

public extension TestServiceProvider where Self == MockTestService {
    static func mock(_ ints: [Int]) ->  Self { .init(ints: ints) }
}

// MARK: Key

public enum TestServiceEnvironmentKey: AsyncStoreEnvironmentKey {
    public static var defaultValue: TestServiceProvider { .empty }
}

public extension AsyncStoreEnvironmentValues {
    var testService: TestServiceProvider {
        get { self[TestServiceEnvironmentKey.self] }
        set { self[TestServiceEnvironmentKey.self] = newValue }
    }
}
