//
//  AsyncExtensions.swift
//  
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation

// MARK: AnyAsyncSequence

public struct AnyAsyncSequence<Element>: AsyncSequence {
    public typealias AsyncIterator = AnyAsyncSequence<Element>.AnyAsyncSequenceIterator
    public typealias Element = Element
    
    private let _makeAsyncIterator: () -> AnyAsyncSequenceIterator
    
    init<S: AsyncSequence>(_ base: S) where S.Element == Element {
        self._makeAsyncIterator = { AnyAsyncSequenceIterator(base.makeAsyncIterator()) }
    }
    
    public func makeAsyncIterator() -> AnyAsyncSequenceIterator {
        self._makeAsyncIterator()
    }
}

public extension AnyAsyncSequence {
    struct AnyAsyncSequenceIterator: AsyncIteratorProtocol {
        private let _next: () async throws -> Element?
        
        init<I: AsyncIteratorProtocol>(_ iterator: I) where I.Element == Element {
            var iterator = iterator
            self._next = { try await iterator.next() }
        }
        
        public mutating func next() async throws -> Element? {
            try await _next()
        }
    }
}

public extension AsyncSequence {
    func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Self.Element> {
        AnyAsyncSequence(self)
    }
}

// MARK: AsyncRemoveDuplicatesSequence

public struct AsyncRemoveDuplicatesSequence<Upstream: AsyncSequence>: AsyncSequence, AsyncIteratorProtocol
where Upstream.Element: Equatable
{
    actor Filter {
        var previousValue: Upstream.Element? = .none
        
        func removeDuplicate(_ value: Upstream.Element) -> Bool {
            defer { previousValue = value }
            guard let prevValue = previousValue else { return true }
            return prevValue != value
        }
    }
    
    public typealias AsyncIterator = AsyncFilterSequence<Upstream>.Iterator
    public typealias Element = Upstream.Element
    
    var iterator: AsyncIterator
    
    init(_ upstream: Upstream) {
        let filter = Filter()
        self.iterator = upstream
            .filter { await filter.removeDuplicate($0) }
            .makeAsyncIterator()
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        iterator
    }
    
    public mutating func next() async throws -> Upstream.Element? {
        try await iterator.next()
    }
}

public extension AsyncSequence where Element: Equatable {
    func removeDuplicates() -> AsyncRemoveDuplicatesSequence<Self> {
        .init(self)
    }
}

// MARK: Extensions

public extension Task where Success == Never, Failure == Never {
    static func trySleep(for timeInterval: TimeInterval?) async throws {
        guard let delay = timeInterval else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
