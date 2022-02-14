//
//  AsyncExtensions.swift
//  
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation

// MARK: AnyAsyncSequence

struct AnyAsyncSequence<Element>: AsyncSequence {
    typealias AsyncIterator = AnyAsyncSequence<Element>.AnyAsyncSequenceIterator
    typealias Element = Element
    
    private let _makeAsyncIterator: () -> AnyAsyncSequenceIterator
    
    init<S: AsyncSequence>(_ base: S) where S.Element == Element {
        self._makeAsyncIterator = { AnyAsyncSequenceIterator(base.makeAsyncIterator()) }
    }
    
    func makeAsyncIterator() -> AnyAsyncSequenceIterator {
        self._makeAsyncIterator()
    }
}

extension AnyAsyncSequence {
    struct AnyAsyncSequenceIterator: AsyncIteratorProtocol {
        private let _next: () async throws -> Element?
        
        init<I: AsyncIteratorProtocol>(_ iterator: I) where I.Element == Element {
            var iterator = iterator
            self._next = { try await iterator.next() }
        }
        
        mutating func next() async throws -> Element? {
            try await _next()
        }
    }
}

extension AsyncSequence {
    func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Self.Element> {
        AnyAsyncSequence(self)
    }
}

// MARK: AsyncRemoveDuplicatesSequence

struct AsyncRemoveDuplicatesSequence<Upstream: AsyncSequence>: AsyncSequence, AsyncIteratorProtocol
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
    
    typealias AsyncIterator = AsyncFilterSequence<Upstream>.Iterator
    typealias Element = Upstream.Element
    
    var iterator: AsyncIterator
    
    init(_ upstream: Upstream) {
        let filter = Filter()
        self.iterator = upstream
            .filter { await filter.removeDuplicate($0) }
            .makeAsyncIterator()
    }
    
    func makeAsyncIterator() -> AsyncIterator {
        iterator
    }
    
    mutating func next() async throws -> Upstream.Element? {
        try await iterator.next()
    }
}

extension AsyncSequence where Element: Equatable {
    func removeDuplicates() -> AsyncRemoveDuplicatesSequence<Self> {
        .init(self)
    }
}


// MARK: Extensions

extension Task where Success == Never, Failure == Never {
    static func trySleep(for timeInterval: TimeInterval?) async throws {
        guard let delay = timeInterval else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
