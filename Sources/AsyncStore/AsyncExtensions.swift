//
//  AsyncExtensions.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation

import Foundation

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
        private let _next: () async -> Element?
        
        init<I: AsyncIteratorProtocol>(_ iterator: I) where I.Element == Element {
            var iterator = iterator
            self._next = { try? await iterator.next() }
        }
        
        public mutating func next() async -> Element? {
            await _next()
        }
    }
}

public extension AsyncSequence {
    func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Self.Element> {
        AnyAsyncSequence(self)
    }
}

extension KeyPath: @unchecked @retroactive Sendable where Root: Sendable, Value: Sendable { }
extension WritableKeyPath: @unchecked @retroactive Sendable where Root: Sendable, Value: Sendable { }
