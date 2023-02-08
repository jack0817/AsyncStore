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

// MARK: DebounceAsyncSequence

struct DebounceAsyncSequence<Upstream: AsyncSequence>: AsyncSequence {
    typealias AsyncIterator = AsyncStream<Upstream.Element>.Iterator
    typealias Element = Upstream.Element

    let upstream: Upstream
    private let debouncer: Debouncer

    init(upstream: Upstream, timeInterval: TimeInterval) {
        self.upstream = upstream
        self.debouncer = Debouncer(
            upstreamIterator: upstream.makeAsyncIterator(),
            timeInterval: timeInterval
        )
    }

    func makeAsyncIterator() -> AsyncStream<Upstream.Element>.Iterator {
        debouncer.stream.makeAsyncIterator()
    }
}

extension DebounceAsyncSequence {
    final class Debouncer {
        public var upstreamIterator: Upstream.AsyncIterator
        public let timeInterval: TimeInterval
        private var elementStream: AsyncStream<Element>! = .none
        private var continuation: AsyncStream<Element>.Continuation! = .none
        private var debounceTask: Task<Void, Never>? = .none

        public var stream: AsyncStream<Element> {
            elementStream
        }

        init(upstreamIterator: Upstream.AsyncIterator, timeInterval: TimeInterval) {
            self.upstreamIterator = upstreamIterator
            self.timeInterval = timeInterval
            self.elementStream = AsyncStream<Upstream.Element> { cont in
                self.continuation = cont
            }

            Task {
                while let element = try? await self.upstreamIterator.next() {
                    debounceTask?.cancel()
                    debounceTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: timeInterval.nanoSeconds)
                            continuation.yield(element)
                        } catch { }
                    }
                }
            }
        }
    }
}

public extension AsyncSequence {
    func debounce(for timeInterval: TimeInterval) -> AnyAsyncSequence<Element> {
        return DebounceAsyncSequence(upstream: self, timeInterval: timeInterval)
            .eraseToAnyAsyncSequence()
    }
}

// MARK: Extensions

public extension Task where Success == Never, Failure == Never {
    static func trySleep(for timeInterval: TimeInterval?) async throws {
        guard let delay = timeInterval else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

extension TimeInterval {
    var nanoSeconds: UInt64 {
        UInt64(1_000_000_000  * self)
    }
}
